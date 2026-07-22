defmodule AnsibleRelay.Identity.AnchorStore do
  @moduledoc """
  Chain-verifying store for self-certifying identity anchors (Task 4, relay).

  The relay STORES and SERVES the user-signed anchor chain but is not its
  authority: every check here is over bytes the user signed, so a *different*
  relay could verify the same chain (design §"Anchor as a Self-Certifying
  Object"; Base Rule 1 — operator is not the sole authority).

  ## Canonical encoding (matched byte-for-byte to the Dart foundation)

  The CID and the signed message are SHA-256 / Ed25519 over the *canonical
  body* — the anchor object minus its signatures. The body is JSON with:

    * keys in a FIXED INSERTION ORDER (NOT sorted):
      `type, schema_version, did, handle, identity_key, custody_class,
       devices, prev_anchor_cid, reason, created_at`
    * each device map keyed in order:
      `device_id, device_key, custody_class, enrolled_at, attestation_sig`
    * no insignificant whitespace; standard JSON scalar encoding; `null` for
      a null `prev_anchor_cid`; integers (`schema_version`) without decimals.

  This mirrors `IdentityAnchor.toCanonicalBody()` /
  `canonicalBodyJson()` in
  `ansible_core/store/lib/src/entities/identity_anchor.dart`, where the Dart
  map literal preserves insertion order and `dart:convert`'s `jsonEncode`
  emits that order with no whitespace. The relay therefore re-emits the body
  in the same order rather than re-encoding the client's JSON (whose key
  order / whitespace is not guaranteed over the wire).

      CID = "sha256:" <> lower_hex(sha256(utf8(canonical_body_json)))

  Confirmed against the Dart source: the field order and the
  `sha256:<hex>` prefix here are a direct transcription of
  `toCanonicalBody()` and `computeCid()`; the relay test
  `identity_anchor_controller_test.exs` independently re-derives the CID from
  a hand-written expected byte string to lock the encoding.

  ## Signature convention

  `sig` is an Ed25519 signature by `identity_key` over the UTF-8 bytes of the
  canonical body, hex-encoded — verified via `AnsibleRelay.SigVerifier`
  (same NIF/OTP path used for op and challenge signatures). Co-signatures
  (rotation old-key, device_change device-key, recovery_proof device-key)
  sign the SAME canonical-body bytes with the relevant key.
  """

  import Ecto.Query

  alias AnsibleRelay.{DidElix, Repo, SigVerifier}
  alias AnsibleRelay.Db.{IdentityAnchor, IdentityAccountFreeze}

  @reasons ~w(initial rotation recovery device_change)
  # v2 (2026-06-16): `also_known_as` joins the signed body, positioned right
  # after `identity_key` to match `IdentityAnchor.toCanonicalBody()` in
  # `ansible_core/store/lib/src/entities/identity_anchor.dart`. The relay MUST
  # re-emit it in this exact slot or the CID/signature will not verify.
  @body_keys_v2 ~w(type schema_version did handle identity_key also_known_as
                   custody_class devices prev_anchor_cid reason created_at)
  @body_keys_v3 ~w(type schema_version did handle identity_key identity_key_algorithm
                   also_known_as custody_class devices prev_anchor_cid reason created_at)
  @device_keys ~w(device_id device_key custody_class enrolled_at attestation_sig)
  # The fields an enrolled device's `attestation_sig` actually signs: the
  # device record MINUS `attestation_sig`, in the same order (design
  # §"Anchor as a Self-Certifying Object"; the leading keys of the Dart
  # `AnchorDeviceRecord.toCanonicalMap`, with the trailing `attestation_sig`
  # dropped from the signed message).
  @device_attestation_keys ~w(device_id device_key custody_class enrolled_at)
  @anchor_type "io.trisaura.identity.anchor"
  @default_grace_seconds 259_200

  # --- Canonical encoding (byte-for-byte with the Dart foundation) ---

  @doc "Canonical body JSON (no signatures), fixed key order, no whitespace."
  def canonical_body(anchor) when is_map(anchor) do
    body_keys(anchor)
    |> Enum.map(fn key -> encode_pair(key, body_value(key, anchor)) end)
    |> wrap_object()
  end

  defp body_keys(anchor) do
    if schema_version(anchor) >= 3, do: @body_keys_v3, else: @body_keys_v2
  end

  defp body_value("type", _anchor), do: @anchor_type
  defp body_value("schema_version", anchor), do: schema_version(anchor)
  defp body_value("also_known_as", anchor), do: also_known_as(anchor)
  defp body_value("devices", anchor), do: {:devices, devices(anchor)}
  defp body_value(key, anchor), do: fetch(anchor, key)

  # A JSON array of alias strings; defaults to [] so the canonical body matches
  # the Dart `also_known_as: const []` default (never `null`).
  defp also_known_as(anchor) do
    case fetch(anchor, "also_known_as") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp schema_version(anchor) do
    case fetch(anchor, "schema_version") do
      nil -> 1
      v when is_integer(v) -> v
      v when is_binary(v) -> String.to_integer(v)
    end
  end

  defp devices(anchor) do
    case fetch(anchor, "devices") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp encode_pair("devices", {:devices, list}) do
    inner = Enum.map_join(list, ",", &canonical_device/1)
    Jason.encode!("devices") <> ":[" <> inner <> "]"
  end

  defp encode_pair(key, value) do
    Jason.encode!(key) <> ":" <> Jason.encode!(value)
  end

  defp canonical_device(device) do
    @device_keys
    |> Enum.map(fn key -> Jason.encode!(key) <> ":" <> Jason.encode!(fetch(device, key)) end)
    |> wrap_object()
  end

  @doc """
  Canonical bytes an enrolled device's `attestation_sig` covers: the device
  record minus `attestation_sig`, fixed key order, no whitespace. The identity
  key signs THIS message to attest the device key.

  Mirrors the Dart `AnchorDeviceRecord.toCanonicalMap`
  (`ansible_core/store/lib/src/entities/identity_anchor.dart`) with the
  trailing `attestation_sig` field excluded from the signed message.
  """
  def device_attestation_message(device) when is_map(device) do
    @device_attestation_keys
    |> Enum.map(fn key -> Jason.encode!(key) <> ":" <> Jason.encode!(fetch(device, key)) end)
    |> wrap_object()
  end

  defp wrap_object(entries), do: "{" <> Enum.join(entries, ",") <> "}"

  @doc "Content identifier of an anchor object: `sha256:<lowercase hex>`."
  def compute_cid(anchor) when is_map(anchor), do: cid_of_body(canonical_body(anchor))

  def cid_of_body(body) when is_binary(body) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, body), case: :lower)
  end

  # Accept both string and atom keys from JSON params / structs.
  defp fetch(map, key) when is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, String.to_existing_atom(key))
    end
  rescue
    ArgumentError -> nil
  end

  # --- Submission entry point ---

  @doc """
  Submit an anchor object (decoded JSON map) plus optional `recovery_proof`.

  Returns one of:

    * `{:ok, :active, anchor}` — accepted and active (initial/rotation/device_change)
    * `{:ok, :pending, anchor}` — recovery held in the grace window
    * `{:error, reason}` where reason is one of
      `:malformed | :unknown_reason | :invalid_signature |
       :invalid_attestation | :invalid_recovery_proof | :conflict |
       :chain_mismatch | :locked`
  """
  def submit(anchor, opts \\ []) when is_map(anchor) do
    recovery_proof = opts[:recovery_proof] || fetch(anchor, "recovery_proof")
    recovery_authorized = opts[:recovery_authorized] == true

    with {:ok, did, reason} <- validate_shape(anchor),
         :ok <- ensure_not_frozen(did),
         :ok <- verify_device_attestations(anchor),
         body = canonical_body(anchor),
         cid = cid_of_body(body) do
      dispatch(reason, anchor, did, body, cid, recovery_proof, recovery_authorized)
    end
  end

  # Every enrolled device record must carry an `attestation_sig` that is a
  # valid Ed25519 signature, BY THIS ANCHOR'S `identity_key`, over the device's
  # canonical record bytes (the record minus `attestation_sig`). This makes the
  # anchor self-certifying for its device set: a rotation / recovery /
  # device_change cannot smuggle in a device key the identity key never
  # attested (design §"Anchor as a Self-Certifying Object"). An anchor with no
  # devices trivially passes.
  defp verify_device_attestations(anchor) do
    identity_key = fetch(anchor, "identity_key")
    algorithm = identity_key_algorithm(anchor)

    if Enum.all?(devices(anchor), &device_attested?(&1, algorithm, identity_key)) do
      :ok
    else
      {:error, :invalid_attestation}
    end
  end

  defp device_attested?(device, algorithm, identity_key) when is_map(device) do
    sig = fetch(device, "attestation_sig")

    is_binary(sig) and sig != "" and
      verify(algorithm, identity_key, device_attestation_message(device), sig)
  end

  defp device_attested?(_device, _algorithm, _identity_key), do: false

  defp identity_key_algorithm(anchor),
    do: fetch(anchor, "identity_key_algorithm") || "ed25519"

  defp ensure_not_frozen(did) do
    if frozen?(did), do: {:error, :locked}, else: :ok
  end

  defp validate_shape(anchor) do
    did = fetch(anchor, "did")
    reason = fetch(anchor, "reason")
    identity_key = fetch(anchor, "identity_key")
    handle = fetch(anchor, "handle")
    sig = fetch(anchor, "sig")
    type = fetch(anchor, "type")
    prev = fetch(anchor, "prev_anchor_cid")

    cond do
      type != @anchor_type -> {:error, :malformed}
      not is_binary(did) or did == "" -> {:error, :malformed}
      not is_binary(identity_key) or identity_key == "" -> {:error, :malformed}
      not is_binary(handle) or handle == "" -> {:error, :malformed}
      not is_binary(sig) or sig == "" -> {:error, :malformed}
      not is_nil(prev) and not is_binary(prev) -> {:error, :malformed}
      not valid_devices?(fetch(anchor, "devices")) -> {:error, :malformed}
      reason not in @reasons -> {:error, :unknown_reason}
      true -> {:ok, did, reason}
    end
  end

  defp valid_devices?(nil), do: true
  defp valid_devices?(list) when is_list(list), do: Enum.all?(list, &valid_device?/1)
  defp valid_devices?(_), do: false

  defp valid_device?(d) when is_map(d) do
    is_binary(fetch(d, "device_id")) and is_binary(fetch(d, "device_key"))
  end

  defp valid_device?(_), do: false

  # --- Reason dispatch ---

  # initial: genesis. null prev, sig by identity_key, no active anchor exists.
  # For a did:elix the genesis is self-certifying: the DID MUST be the hash of
  # this anchor's own identity_key + handle (DidElix.matches?), so the canonical
  # identifier can never be claimed for a key that didn't generate it. This is
  # what makes a genesis anchor verifiable by any relay without trusting us.
  defp dispatch("initial", anchor, did, body, cid, _proof, _recovery_authorized) do
    cond do
      not is_nil(fetch(anchor, "prev_anchor_cid")) ->
        {:error, :chain_mismatch}

      not genesis_did_self_certifies?(anchor, did) ->
        {:error, :did_mismatch}

      active_anchor(did) != nil ->
        {:error, :conflict}

      not verify(
        identity_key_algorithm(anchor),
        fetch(anchor, "identity_key"),
        body,
        fetch(anchor, "sig")
      ) ->
        {:error, :invalid_signature}

      true ->
        insert_active(anchor, did, body, cid, "initial")
    end
  end

  # rotation: new anchor signed by BOTH the prior active identity_key AND the
  # new identity_key. Possession of the old key is full authority → swap now.
  defp dispatch("rotation", anchor, did, body, cid, _proof, _recovery_authorized) do
    with {:ok, prev} <- require_chain_link(anchor, did),
         new_key = fetch(anchor, "identity_key"),
         old_sig = fetch(anchor, "device_sig"),
         true <-
           verify(identity_key_algorithm(anchor), new_key, body, fetch(anchor, "sig")) ||
             {:error, :invalid_signature},
         true <-
           verify(prev.identity_key_algorithm || "ed25519", prev.identity_key, body, old_sig) ||
             {:error, :invalid_signature} do
      swap_in_active(anchor, did, body, cid, "rotation", prev)
    else
      {:error, _} = err -> err
    end
  end

  # device_change: valid new/current identity signature plus high-authority
  # approval from the active identity key. A legacy enrolled device signature
  # remains accepted during migration. Immediate.
  defp dispatch("device_change", anchor, did, body, cid, _proof, _recovery_authorized) do
    with {:ok, prev} <- require_chain_link(anchor, did),
         true <-
           verify(
             identity_key_algorithm(anchor),
             fetch(anchor, "identity_key"),
             body,
             fetch(anchor, "sig")
           ) ||
             {:error, :invalid_signature},
         device_sig = fetch(anchor, "device_sig"),
         true <- active_authority_signed?(prev, body, device_sig) || {:error, :invalid_signature} do
      swap_in_active(anchor, did, body, cid, "device_change", prev)
    else
      {:error, _} = err -> err
    end
  end

  # recovery (path a): recovery_proof is a signature by the PREVIOUS active
  # identity key (or a legacy enrolled device key during migration). Path b is
  # authorized by an atomically consumed recovery code. Neither is immediate:
  # both are held pending for the grace window and all devices are alerted.
  defp dispatch("recovery", anchor, did, body, cid, recovery_proof, recovery_authorized) do
    with {:ok, prev} <- require_chain_link(anchor, did),
         true <-
           verify(
             identity_key_algorithm(anchor),
             fetch(anchor, "identity_key"),
             body,
             fetch(anchor, "sig")
           ) ||
             {:error, :invalid_signature},
         true <-
           recovery_authorized || active_authority_signed?(prev, body, recovery_proof) ||
             {:error, :invalid_recovery_proof} do
      insert_pending_recovery(anchor, did, body, cid, prev)
    else
      {:error, _} = err -> err
    end
  end

  # did:elix genesis must hash to its own (identity_key, handle, custody_class).
  # Non-elix DIDs (e.g. a did:plc bridge alias anchoring) are not gated here.
  defp genesis_did_self_certifies?(anchor, "did:elix:" <> _ = did) do
    DidElix.matches?(
      did,
      fetch(anchor, "identity_key"),
      fetch(anchor, "handle"),
      fetch(anchor, "custody_class") || "software",
      identity_key_algorithm(anchor)
    )
  end

  defp genesis_did_self_certifies?(_anchor, _did), do: true

  defp require_chain_link(anchor, did) do
    prev = active_anchor(did)
    prev_cid = fetch(anchor, "prev_anchor_cid")

    cond do
      prev == nil -> {:error, :conflict}
      not is_binary(prev_cid) -> {:error, :chain_mismatch}
      prev_cid != prev.anchor_cid -> {:error, :chain_mismatch}
      true -> {:ok, prev}
    end
  end

  defp active_authority_signed?(_prev, _body, nil), do: false
  defp active_authority_signed?(_prev, _body, ""), do: false

  defp active_authority_signed?(prev, body, sig) do
    verify(prev.identity_key_algorithm || "ed25519", prev.identity_key, body, sig) or
      prev
      |> enrolled_device_keys()
      |> Enum.any?(fn key -> verify("ed25519", key, body, sig) end)
  end

  defp enrolled_device_keys(%IdentityAnchor{devices: %{"records" => records}})
       when is_list(records) do
    records |> Enum.map(&fetch(&1, "device_key")) |> Enum.filter(&is_binary/1)
  end

  defp enrolled_device_keys(_), do: []

  # --- Persistence transitions ---

  defp insert_active(anchor, did, body, cid, reason) do
    attrs = anchor_attrs(anchor, did, body, cid, reason, "active", nil)

    case insert_anchor(attrs) do
      {:ok, row} ->
        sync_cache(row)
        AnsibleRelay.Metrics.inc("identity_reanchor_total", %{reason: reason})
        audit_transition(row, reason)
        {:ok, :active, row}

      {:error, _changeset} ->
        {:error, :conflict}
    end
  end

  defp swap_in_active(anchor, did, body, cid, reason, prev) do
    attrs = anchor_attrs(anchor, did, body, cid, reason, "active", nil)

    result =
      Repo.transaction(fn ->
        # Supersede the prior active anchor first so the one-active-per-DID
        # partial unique index never collides.
        Repo.update_all(
          from(a in IdentityAnchor, where: a.did == ^did and a.anchor_cid == ^prev.anchor_cid),
          set: [state: "superseded", updated_at: DateTime.utc_now()]
        )

        case insert_anchor(attrs) do
          {:ok, row} -> row
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, row} ->
        sync_cache(row)
        AnsibleRelay.Metrics.inc("identity_reanchor_total", %{reason: reason})
        audit_transition(row, reason)
        {:ok, :active, row}

      {:error, _} ->
        {:error, :conflict}
    end
  end

  defp insert_pending_recovery(anchor, did, body, cid, _prev) do
    grace_until = DateTime.add(DateTime.utc_now(), grace_seconds(), :second)
    attrs = anchor_attrs(anchor, did, body, cid, "recovery", "pending", grace_until)

    case insert_anchor(attrs) do
      {:ok, row} ->
        AnsibleRelay.Metrics.inc("identity_reanchor_total", %{reason: "recovery"})
        AnsibleRelay.Metrics.inc("identity_recovery_pending_total")
        # Hijack resistance: alert ALL enrolled devices of the DID via the
        # existing content-free wake push, reason-coded `identity_alert`.
        AnsibleRelay.Identity.AnchorAlerts.recovery_pending(did)
        audit_transition(row, "recovery_pending")
        {:ok, :pending, row}

      {:error, _changeset} ->
        {:error, :conflict}
    end
  end

  defp anchor_attrs(anchor, did, body, cid, reason, state, grace_until) do
    %{
      did: did,
      anchor_cid: cid,
      prev_anchor_cid: fetch(anchor, "prev_anchor_cid"),
      reason: reason,
      identity_key: fetch(anchor, "identity_key"),
      identity_key_algorithm: identity_key_algorithm(anchor),
      handle: fetch(anchor, "handle"),
      also_known_as: also_known_as(anchor),
      custody_class: fetch(anchor, "custody_class") || "software",
      schema_version: schema_version(anchor),
      devices: %{"records" => devices(anchor)},
      sig: fetch(anchor, "sig"),
      device_sig: fetch(anchor, "device_sig"),
      canonical_body: body,
      state: state,
      grace_until: grace_until,
      created_at: parse_created_at(fetch(anchor, "created_at"))
    }
  end

  defp parse_created_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_created_at(_), do: DateTime.utc_now()

  defp insert_anchor(attrs) do
    %IdentityAnchor{}
    |> IdentityAnchor.changeset(attrs)
    |> Repo.insert()
  end

  # --- Promote / veto ---

  @doc """
  Promote pending recovery anchors whose grace window has elapsed to active,
  superseding the prior active anchor. Cron-able / test-callable.

  Frozen DIDs are skipped. Returns `{:ok, promoted_cids}`.
  """
  def promote_due(now \\ DateTime.utc_now()) do
    due =
      Repo.all(
        from(a in IdentityAnchor,
          where: a.state == "pending" and not is_nil(a.grace_until) and a.grace_until <= ^now
        )
      )

    promoted =
      due
      |> Enum.filter(fn a -> not frozen?(a.did) end)
      |> Enum.flat_map(fn pending ->
        case promote_one(pending) do
          {:ok, cid} -> [cid]
          _ -> []
        end
      end)

    {:ok, promoted}
  end

  defp promote_one(pending) do
    result =
      Repo.transaction(fn ->
        Repo.update_all(
          from(a in IdentityAnchor, where: a.did == ^pending.did and a.state == "active"),
          set: [state: "superseded", updated_at: DateTime.utc_now()]
        )

        {1, _} =
          Repo.update_all(
            from(a in IdentityAnchor,
              where: a.did == ^pending.did and a.anchor_cid == ^pending.anchor_cid
            ),
            set: [state: "active", grace_until: nil, updated_at: DateTime.utc_now()]
          )

        Repo.get_by!(IdentityAnchor, did: pending.did, anchor_cid: pending.anchor_cid)
      end)

    case result do
      {:ok, row} ->
        sync_cache(row)
        audit_transition(row, "recovery_promoted")
        AnsibleRelay.Identity.AnchorAlerts.recovery_promoted(row.did)
        {:ok, row.anchor_cid}

      other ->
        other
    end
  end

  @doc """
  Veto a pending recovery anchor. `veto_sig` must be a valid Ed25519
  signature, over the pending anchor's canonical body, by ANY
  previously-enrolled identity_key or device key of the DID. On success the
  pending anchor becomes `vetoed` and the account is FROZEN.

  Returns `:ok | {:error, :not_found | :invalid_signature | :locked}`.
  """
  def veto(did, pending_anchor_cid, veto_sig)
      when is_binary(did) and is_binary(pending_anchor_cid) do
    cond do
      frozen?(did) ->
        {:error, :locked}

      true ->
        case Repo.get_by(IdentityAnchor,
               did: did,
               anchor_cid: pending_anchor_cid,
               state: "pending"
             ) do
          nil ->
            {:error, :not_found}

          pending ->
            if veto_sig_valid?(did, pending.canonical_body, veto_sig) do
              do_veto(pending)
            else
              {:error, :invalid_signature}
            end
        end
    end
  end

  defp do_veto(pending) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      Repo.update_all(
        from(a in IdentityAnchor,
          where: a.did == ^pending.did and a.anchor_cid == ^pending.anchor_cid
        ),
        set: [state: "vetoed", grace_until: nil, updated_at: now]
      )

      %IdentityAccountFreeze{}
      |> IdentityAccountFreeze.changeset(%{
        did: pending.did,
        reason: "veto",
        vetoed_anchor_cid: pending.anchor_cid,
        frozen_at: now
      })
      |> Repo.insert(on_conflict: :nothing, conflict_target: :did)
    end)

    AnsibleRelay.Metrics.inc("identity_veto_total")

    AnsibleRelay.Identity.RecoveryStore.audit!(
      pending.did,
      "recovery_vetoed",
      "enrolled_key_veto",
      pending.anchor_cid
    )

    AnsibleRelay.Identity.AnchorAlerts.recovery_vetoed(pending.did)

    :ok
  end

  # A veto is authorized by any key the DID has EVER enrolled: every prior
  # anchor's identity_key plus every device key in every prior anchor.
  defp veto_sig_valid?(did, body, sig) do
    did
    |> previously_enrolled_keys()
    |> Enum.any?(fn key -> verify("ed25519", key, body, sig) end)
  end

  defp previously_enrolled_keys(did) do
    anchors =
      Repo.all(
        from(a in IdentityAnchor,
          where: a.did == ^did and a.state in ["active", "superseded", "vetoed"]
        )
      )

    identity_keys = Enum.map(anchors, & &1.identity_key)

    device_keys =
      anchors
      |> Enum.flat_map(fn a ->
        case a.devices do
          %{"records" => records} when is_list(records) ->
            records |> Enum.map(&fetch(&1, "device_key"))

          _ ->
            []
        end
      end)
      |> Enum.filter(&is_binary/1)

    Enum.uniq(identity_keys ++ device_keys)
  end

  # --- Reads (the cache) ---

  @doc "The current ACTIVE anchor row for a DID, or nil."
  def active_anchor(did) when is_binary(did) do
    Repo.get_by(IdentityAnchor, did: did, state: "active")
  end

  @doc "Serve the active anchor as a public object map, or an error tuple."
  def get_active(did) when is_binary(did) do
    cond do
      frozen?(did) -> {:error, :locked}
      anchor = active_anchor(did) -> {:ok, to_object(anchor)}
      true -> {:error, :not_found}
    end
  end

  @doc """
  The pending recovery re-anchor for a DID, if any — the veto UX on enrolled
  devices polls this to learn a recovery is in its grace window. Returns the
  public pending facts plus the stored `canonical_body`, which is exactly the
  byte string a veto signature must cover (`veto_sig_valid?/3`).

  Not gated on `frozen?`: after a veto the pending row is gone (state
  `vetoed`), so this naturally 404s; serving it while frozen would only
  confuse the poller.
  """
  def get_pending(did) when is_binary(did) do
    row =
      Repo.one(
        from(a in IdentityAnchor,
          where: a.did == ^did and a.state == "pending",
          order_by: [desc: a.inserted_at],
          limit: 1
        )
      )

    case row do
      nil ->
        {:error, :not_found}

      pending ->
        {:ok,
         %{
           "anchor_cid" => pending.anchor_cid,
           "reason" => pending.reason,
           "grace_until" => pending.grace_until && DateTime.to_iso8601(pending.grace_until),
           "canonical_body" => pending.canonical_body
         }}
    end
  end

  @doc "Reconstruct the on-the-wire anchor object map from a stored row."
  def to_object(%IdentityAnchor{} = a) do
    base = %{
      "type" => @anchor_type,
      "schema_version" => a.schema_version,
      "did" => a.did,
      "handle" => a.handle,
      "identity_key" => a.identity_key,
      "identity_key_algorithm" => a.identity_key_algorithm || "ed25519",
      "also_known_as" => a.also_known_as || [],
      "custody_class" => a.custody_class,
      "devices" => device_records(a),
      "prev_anchor_cid" => a.prev_anchor_cid,
      "reason" => a.reason,
      "created_at" => DateTime.to_iso8601(a.created_at),
      "anchor_cid" => a.anchor_cid,
      "state" => a.state,
      "sig" => a.sig
    }

    if a.device_sig, do: Map.put(base, "device_sig", a.device_sig), else: base
  end

  defp device_records(%IdentityAnchor{devices: %{"records" => records}}) when is_list(records),
    do: records

  defp device_records(_), do: []

  @doc "True if the DID is frozen by a veto."
  def frozen?(did) when is_binary(did) do
    Repo.exists?(from(f in IdentityAccountFreeze, where: f.did == ^did))
  end

  # --- did_accounts cache wiring ---

  # When an anchor becomes active, refresh the did_accounts cache row from it
  # (design: `did_accounts` becomes a cache of the latest anchor). Existing
  # readers (`DidAccountCache.public_key_hex/1`, handle index) keep working.
  defp sync_cache(%IdentityAnchor{} = a) do
    previous = AnsibleRelay.DidAccountCache.get(a.did)

    key_version =
      case previous do
        {:ok, entry} -> Map.get(entry, :key_version, 1)
        _ -> 1
      end

    AnsibleRelay.DidAccountCache.put(a.did, a.identity_key, a.handle,
      signing_algorithm: a.identity_key_algorithm || "ed25519",
      key_version: key_version
    )

    :ok
  rescue
    _ -> :ok
  end

  # --- Signature primitive ---

  defp verify(algorithm, public_key_hex, message, sig_hex)
       when is_binary(algorithm) and is_binary(public_key_hex) and is_binary(message) and
              is_binary(sig_hex) do
    SigVerifier.verify_identity(algorithm, public_key_hex, message, sig_hex)
  end

  defp verify(_algorithm, _pk, _msg, _sig), do: false

  defp grace_seconds do
    Application.get_env(:ansible_relay, :identity_recovery_grace_seconds, @default_grace_seconds)
  end

  defp audit_transition(row, reason) do
    event_type =
      case reason do
        "device_change" -> "devices_changed"
        "rotation" -> "identity_rotated"
        "recovery_pending" -> "recovery_pending"
        "recovery_promoted" -> "recovery_promoted"
        _ -> "identity_anchor_created"
      end

    AnsibleRelay.Identity.RecoveryStore.audit!(
      row.did,
      event_type,
      reason,
      row.anchor_cid
    )
  end

  @doc false
  def reset do
    Repo.delete_all(AnsibleRelay.Db.IdentityRecoveryAuditEvent)
    Repo.delete_all(AnsibleRelay.Db.IdentityRecoveryCode)
    Repo.delete_all(IdentityAnchor)
    Repo.delete_all(IdentityAccountFreeze)
    :ok
  end
end
