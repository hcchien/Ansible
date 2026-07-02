defmodule AnsibleRelay.Web.IdentityAnchorControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Identity.AnchorStore
  alias AnsibleRelay.Push.{TestSender, TokenRegistry}
  alias AnsibleRelay.Repo
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])
  @anchor_type "io.trisaura.identity.anchor"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    for mod <- [AnsibleRelay.DidAccountCache] do
      case mod.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end

    AnsibleRelay.DidAccountCache.reset()
    TestSender.reset()
    :ok = TokenRegistry.reset()
    :ok = AnchorStore.reset()
    :ok
  end

  # --- Crypto helpers (keys generated in-test) ---

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  # --- Canonical body built the SAME way as the Dart foundation ---
  # Fixed key order, no whitespace; this is what gets hashed (CID) and signed.

  defp canonical_body(anchor) do
    devices_json =
      "[" <>
        Enum.map_join(anchor.devices, ",", fn d ->
          "{" <>
            Enum.map_join(
              [
                {"device_id", d.device_id},
                {"device_key", d.device_key},
                {"custody_class", d.custody_class},
                {"enrolled_at", d.enrolled_at},
                {"attestation_sig", d.attestation_sig}
              ],
              ",",
              fn {k, v} -> Jason.encode!(k) <> ":" <> Jason.encode!(v) end
            ) <> "}"
        end) <> "]"

    [
      {"type", Jason.encode!(@anchor_type)},
      {"schema_version", Integer.to_string(anchor.schema_version)},
      {"did", Jason.encode!(anchor.did)},
      {"handle", Jason.encode!(anchor.handle)},
      {"identity_key", Jason.encode!(anchor.identity_key)},
      {"also_known_as", Jason.encode!(anchor.also_known_as || [])},
      {"custody_class", Jason.encode!(anchor.custody_class)},
      {"devices", devices_json},
      {"prev_anchor_cid", Jason.encode!(anchor.prev_anchor_cid)},
      {"reason", Jason.encode!(anchor.reason)},
      {"created_at", Jason.encode!(anchor.created_at)}
    ]
    |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> v end)
    |> then(&("{" <> &1 <> "}"))
  end

  defp cid(body), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, body), case: :lower)

  # Build an anchor map ready for POST, signed by identity_key (+ optional cosig).
  defp build_anchor(fields, identity_priv, opts \\ []) do
    anchor =
      Map.merge(
        %{
          schema_version: 1,
          custody_class: "software",
          also_known_as: [],
          devices: [],
          prev_anchor_cid: nil,
          created_at: "2026-06-13T09:00:00.000Z"
        },
        fields
      )

    body = canonical_body(anchor)
    anchor_cid = cid(body)

    sig = sign(identity_priv, body)

    base = %{
      "type" => @anchor_type,
      "schema_version" => anchor.schema_version,
      "did" => anchor.did,
      "handle" => anchor.handle,
      "identity_key" => anchor.identity_key,
      "also_known_as" => anchor.also_known_as,
      "custody_class" => anchor.custody_class,
      "devices" =>
        Enum.map(anchor.devices, fn d ->
          %{
            "device_id" => d.device_id,
            "device_key" => d.device_key,
            "custody_class" => d.custody_class,
            "enrolled_at" => d.enrolled_at,
            "attestation_sig" => d.attestation_sig
          }
        end),
      "prev_anchor_cid" => anchor.prev_anchor_cid,
      "reason" => anchor.reason,
      "created_at" => anchor.created_at,
      "sig" => sig
    }

    base =
      case opts[:device_sig] do
        nil -> base
        device_sig -> Map.put(base, "device_sig", device_sig)
      end

    {base, anchor_cid, body}
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp get_req(path) do
    conn(:get, path)
    |> Router.call(@router_opts)
  end

  # Canonical bytes a device's attestation_sig signs: the device record MINUS
  # attestation_sig, fixed order, no whitespace. Re-derived here independently
  # (matching the Dart AnchorDeviceRecord.toCanonicalMap leading keys) so the
  # test locks the exact signed bytes rather than trusting the store helper.
  defp device_attestation_message(d) do
    [
      {"device_id", d.device_id},
      {"device_key", d.device_key},
      {"custody_class", d.custody_class},
      {"enrolled_at", d.enrolled_at}
    ]
    |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> Jason.encode!(v) end)
    |> then(&("{" <> &1 <> "}"))
  end

  # An enrolled device record whose attestation_sig is a valid signature by the
  # anchor's identity key (id_priv) over the device record. Pass `attest_priv`
  # to forge an attestation by a DIFFERENT key (the smuggled-device case).
  defp device_record(device_pub, id_priv, opts \\ []) do
    attest_priv = opts[:attest_priv] || id_priv

    base = %{
      device_id: "dev-#{System.unique_integer([:positive])}",
      device_key: device_pub,
      custody_class: "software",
      enrolled_at: "2026-06-13T08:00:00.000Z"
    }

    Map.put(base, :attestation_sig, sign(attest_priv, device_attestation_message(base)))
  end

  # Helper: create an initial anchor with one enrolled device. Returns the
  # context needed to chain further anchors.
  defp seed_initial(opts \\ []) do
    did = "did:plc:anchor_#{System.unique_integer([:positive])}"
    handle = "anchor#{System.unique_integer([:positive])}.elix.cool"
    {id_pub, id_priv} = ed25519_keypair()
    {dev_pub, dev_priv} = ed25519_keypair()

    devices = if opts[:with_device], do: [device_record(dev_pub, id_priv)], else: []

    {anchor, anchor_cid, _body} =
      build_anchor(
        %{
          did: did,
          handle: handle,
          identity_key: id_pub,
          reason: "initial",
          devices: devices
        },
        id_priv
      )

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 201

    %{
      did: did,
      handle: handle,
      id_pub: id_pub,
      id_priv: id_priv,
      dev_pub: dev_pub,
      dev_priv: dev_priv,
      anchor_cid: anchor_cid
    }
  end

  # =========================================================================
  # Canonical encoding lock — re-derive the CID from a hand-written byte
  # string to prove the relay hashes the SAME bytes the Dart app signs.
  # =========================================================================

  test "canonical body + CID match the Dart foundation byte-for-byte" do
    anchor = %{
      "type" => @anchor_type,
      "schema_version" => 2,
      "did" => "did:elix:alice123",
      "handle" => "alice.elix.cool",
      "identity_key" => String.duplicate("aa", 32),
      "also_known_as" => ["at://alice.elix.cool", "did:key:zABC"],
      "custody_class" => "software",
      "devices" => [
        %{
          "device_id" => "dev-1",
          "device_key" => String.duplicate("bb", 32),
          "custody_class" => "software",
          "enrolled_at" => "2026-06-13T10:00:00.000Z",
          "attestation_sig" => String.duplicate("cc", 64)
        }
      ],
      "prev_anchor_cid" => nil,
      "reason" => "initial",
      "created_at" => "2026-06-13T09:00:00.000Z"
    }

    expected_body =
      ~s({"type":"io.trisaura.identity.anchor","schema_version":2,) <>
        ~s("did":"did:elix:alice123","handle":"alice.elix.cool",) <>
        ~s("identity_key":"#{String.duplicate("aa", 32)}",) <>
        ~s("also_known_as":["at://alice.elix.cool","did:key:zABC"],) <>
        ~s("custody_class":"software",) <>
        ~s("devices":[{"device_id":"dev-1","device_key":"#{String.duplicate("bb", 32)}",) <>
        ~s("custody_class":"software","enrolled_at":"2026-06-13T10:00:00.000Z",) <>
        ~s("attestation_sig":"#{String.duplicate("cc", 64)}"}],) <>
        ~s("prev_anchor_cid":null,"reason":"initial","created_at":"2026-06-13T09:00:00.000Z"})

    assert AnchorStore.canonical_body(anchor) == expected_body

    expected_cid =
      "sha256:" <> Base.encode16(:crypto.hash(:sha256, expected_body), case: :lower)

    assert AnchorStore.compute_cid(anchor) == expected_cid
  end

  # =========================================================================
  # initial
  # =========================================================================

  test "initial: valid identity_key sig is accepted and active (201)" do
    ctx = seed_initial()

    assert {:ok, object} = AnchorStore.get_active(ctx.did)
    assert object["anchor_cid"] == ctx.anchor_cid
    assert object["reason"] == "initial"
    assert object["state"] == "active"
  end

  test "resolve_did projects a W3C DID document from the active anchor" do
    {id_pub, id_priv} = ed25519_keypair()
    # Genesis did:elix must self-certify (hash of identity_key + handle).
    did = AnsibleRelay.DidElix.derive(id_pub, "res.elix.cool")
    aka = ["at://res.elix.cool", "did:key:zRESOLVEKEY"]

    {anchor, _cid, _body} =
      build_anchor(
        %{
          did: did,
          handle: "res.elix.cool",
          identity_key: id_pub,
          reason: "initial",
          also_known_as: aka
        },
        id_priv
      )

    assert post_json("/api/v1/identity/anchor", anchor).status == 201

    resp = get_req("/api/v1/identity/did/#{did}")
    assert resp.status == 200
    doc = Jason.decode!(resp.resp_body)

    assert doc["id"] == did
    assert doc["alsoKnownAs"] == aka
    assert [vm] = doc["verificationMethod"]
    assert vm["controller"] == did
    assert vm["type"] == "Ed25519VerificationKey2020"
    assert vm["publicKeyMultibase"] == "zRESOLVEKEY"
    assert [svc] = doc["service"]
    assert svc["type"] == "AnsibleRelay"
  end

  test "initial: duplicate active anchor for the same DID conflicts (409)" do
    did = "did:plc:dup_#{System.unique_integer([:positive])}"
    {id_pub, id_priv} = ed25519_keypair()

    {anchor, _cid, _body} =
      build_anchor(
        %{did: did, handle: "dup.elix.cool", identity_key: id_pub, reason: "initial"},
        id_priv
      )

    assert post_json("/api/v1/identity/anchor", anchor).status == 201

    # A second initial anchor (new created_at → new CID) must conflict.
    {anchor2, _cid2, _body2} =
      build_anchor(
        %{
          did: did,
          handle: "dup.elix.cool",
          identity_key: id_pub,
          reason: "initial",
          created_at: "2026-06-14T09:00:00.000Z"
        },
        id_priv
      )

    resp = post_json("/api/v1/identity/anchor", anchor2)
    assert resp.status == 409
    assert Jason.decode!(resp.resp_body)["error"] == "conflict"
  end

  test "initial: a bad identity signature is rejected (401)" do
    did = "did:plc:badsig_#{System.unique_integer([:positive])}"
    {id_pub, _id_priv} = ed25519_keypair()
    {_other_pub, other_priv} = ed25519_keypair()

    # Sign with the wrong key.
    {anchor, _cid, _body} =
      build_anchor(
        %{did: did, handle: "badsig.elix.cool", identity_key: id_pub, reason: "initial"},
        other_priv
      )

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 401
    assert Jason.decode!(resp.resp_body)["error"] == "invalid_signature"
  end

  # =========================================================================
  # rotation
  # =========================================================================

  test "rotation: sigs by BOTH old and new identity keys swap immediately (200)" do
    ctx = seed_initial()
    {new_pub, new_priv} = ed25519_keypair()

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: new_pub,
      reason: "rotation",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z"
    }

    # Build with new key sig in `sig`; cosign with the OLD key in `device_sig`.
    {anchor, new_cid, body} = build_anchor(fields, new_priv)
    old_sig = sign(ctx.id_priv, body)
    anchor = Map.put(anchor, "device_sig", old_sig)

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 200
    body_out = Jason.decode!(resp.resp_body)
    assert body_out["state"] == "active"
    assert body_out["anchor_cid"] == new_cid

    # The new anchor is the active cache; the prior is superseded.
    assert {:ok, object} = AnchorStore.get_active(ctx.did)
    assert object["identity_key"] == new_pub
    assert object["reason"] == "rotation"
    # did_accounts cache reflects the new identity key.
    assert AnsibleRelay.DidAccountCache.public_key_hex(ctx.did) == new_pub
  end

  test "rotation: missing the old-key co-signature is rejected (401)" do
    ctx = seed_initial()
    {new_pub, new_priv} = ed25519_keypair()

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: new_pub,
      reason: "rotation",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z"
    }

    # Only the new key signs; no `device_sig` for the old key.
    {anchor, _cid, _body} = build_anchor(fields, new_priv)

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 401
    assert Jason.decode!(resp.resp_body)["error"] == "invalid_signature"
  end

  # =========================================================================
  # device_change
  # =========================================================================

  test "device_change: identity sig + enrolled device sig is immediate (200)" do
    ctx = seed_initial(with_device: true)

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: ctx.id_pub,
      reason: "device_change",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z"
    }

    {anchor, new_cid, body} = build_anchor(fields, ctx.id_priv)
    device_sig = sign(ctx.dev_priv, body)
    anchor = Map.put(anchor, "device_sig", device_sig)

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 200
    assert Jason.decode!(resp.resp_body)["anchor_cid"] == new_cid

    assert {:ok, object} = AnchorStore.get_active(ctx.did)
    assert object["reason"] == "device_change"
  end

  test "device_change: a signature by a non-enrolled device is rejected (401)" do
    ctx = seed_initial(with_device: true)
    {_stranger_pub, stranger_priv} = ed25519_keypair()

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: ctx.id_pub,
      reason: "device_change",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z"
    }

    {anchor, _cid, body} = build_anchor(fields, ctx.id_priv)
    anchor = Map.put(anchor, "device_sig", sign(stranger_priv, body))

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 401
    assert Jason.decode!(resp.resp_body)["error"] == "invalid_signature"
  end

  # =========================================================================
  # recovery — grace window, alert, promote, veto
  # =========================================================================

  defp register_device_for(did) do
    {:ok, _} =
      TokenRegistry.register(%{
        subject_did: did,
        device_id: "push_#{System.unique_integer([:positive])}",
        push_token: "tok_#{did}",
        platform: "fcm",
        categories: ["messenger"]
      })
  end

  defp build_recovery(ctx) do
    {new_pub, new_priv} = ed25519_keypair()

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: new_pub,
      reason: "recovery",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z"
    }

    {anchor, new_cid, body} = build_anchor(fields, new_priv)
    # recovery_proof: an enrolled device key from the previous anchor signs.
    recovery_proof = sign(ctx.dev_priv, body)
    anchor = Map.put(anchor, "recovery_proof", recovery_proof)
    {anchor, new_cid, new_pub}
  end

  test "recovery: held pending with grace_until and alerts all enrolled devices (202)" do
    ctx = seed_initial(with_device: true)
    register_device_for(ctx.did)

    {anchor, new_cid, _new_pub} = build_recovery(ctx)

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 202
    body_out = Jason.decode!(resp.resp_body)
    assert body_out["state"] == "pending"
    assert body_out["anchor_cid"] == new_cid
    assert is_binary(body_out["grace_until"])

    # The active cache is still the ORIGINAL anchor — recovery is not immediate.
    assert {:ok, object} = AnchorStore.get_active(ctx.did)
    assert object["identity_key"] == ctx.id_pub

    # All enrolled devices were alerted via the content-free wake push.
    calls = TestSender.calls()
    assert [%{token: "tok_" <> _, payload: payload}] = calls
    assert payload == %{"hint" => "sync"}
  end

  test "recovery: an invalid recovery_proof is rejected (401)" do
    ctx = seed_initial(with_device: true)
    {_bad_pub, bad_priv} = ed25519_keypair()

    {new_pub, new_priv} = ed25519_keypair()

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: new_pub,
      reason: "recovery",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z"
    }

    {anchor, _cid, body} = build_anchor(fields, new_priv)
    # Proof signed by a key that is NOT an enrolled device.
    anchor = Map.put(anchor, "recovery_proof", sign(bad_priv, body))

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 401
    assert Jason.decode!(resp.resp_body)["error"] == "invalid_recovery_proof"
  end

  test "recovery → promote after grace → active" do
    ctx = seed_initial(with_device: true)
    register_device_for(ctx.did)

    {anchor, new_cid, new_pub} = build_recovery(ctx)
    assert post_json("/api/v1/identity/anchor", anchor).status == 202

    # Force the grace window to have elapsed by promoting at a future instant.
    future = DateTime.add(DateTime.utc_now(), 400_000, :second)
    assert {:ok, promoted} = AnchorStore.promote_due(future)
    assert new_cid in promoted

    assert {:ok, object} = AnchorStore.get_active(ctx.did)
    assert object["identity_key"] == new_pub
    assert object["reason"] == "recovery"
    assert object["state"] == "active"
  end

  test "pending endpoint exposes the grace-window recovery and clears after veto" do
    ctx = seed_initial(with_device: true)

    # No pending yet → 404 (and "pending" is not swallowed by the :did route).
    assert get_req("/api/v1/identity/anchor/#{ctx.did}/pending").status == 404

    {anchor, new_cid, _new_pub} = build_recovery(ctx)
    assert post_json("/api/v1/identity/anchor", anchor).status == 202

    resp = get_req("/api/v1/identity/anchor/#{ctx.did}/pending")
    assert resp.status == 200
    body = Jason.decode!(resp.resp_body)
    assert body["anchor_cid"] == new_cid
    assert body["reason"] == "recovery"
    assert is_binary(body["grace_until"])
    assert is_binary(body["canonical_body"])

    # A veto signed over exactly the served canonical_body verifies — the veto
    # UX signs these bytes without reconstructing the anchor locally.
    veto_sig = sign(ctx.id_priv, body["canonical_body"])

    assert post_json("/api/v1/identity/anchor/veto", %{
             "did" => ctx.did,
             "pending_anchor_cid" => new_cid,
             "veto_sig" => veto_sig
           }).status == 200

    assert get_req("/api/v1/identity/anchor/#{ctx.did}/pending").status == 404
  end

  test "veto before grace freezes the account and locks further re-anchors (423)" do
    ctx = seed_initial(with_device: true)
    register_device_for(ctx.did)

    {anchor, new_cid, _new_pub} = build_recovery(ctx)
    assert post_json("/api/v1/identity/anchor", anchor).status == 202

    # The original identity key vetoes (a previously-enrolled key).
    pending = Repo.get_by!(AnsibleRelay.Db.IdentityAnchor, did: ctx.did, anchor_cid: new_cid)
    veto_sig = sign(ctx.id_priv, pending.canonical_body)

    resp =
      post_json("/api/v1/identity/anchor/veto", %{
        "did" => ctx.did,
        "pending_anchor_cid" => new_cid,
        "veto_sig" => veto_sig
      })

    assert resp.status == 200
    assert Jason.decode!(resp.resp_body)["frozen"] == true

    # The account is frozen: GET is 423 and a new auto re-anchor is rejected.
    assert get_req("/api/v1/identity/anchor/#{ctx.did}").status == 423

    {anchor2, _cid2, _pub2} = build_recovery(ctx)
    resp2 = post_json("/api/v1/identity/anchor", anchor2)
    assert resp2.status == 423
    assert Jason.decode!(resp2.resp_body)["error"] == "account_frozen"

    # Promote must NOT resurrect a vetoed/frozen account.
    future = DateTime.add(DateTime.utc_now(), 400_000, :second)
    {:ok, promoted} = AnchorStore.promote_due(future)
    assert promoted == []
  end

  test "veto with a signature by a never-enrolled key is rejected (401)" do
    ctx = seed_initial(with_device: true)
    {anchor, new_cid, _pub} = build_recovery(ctx)
    assert post_json("/api/v1/identity/anchor", anchor).status == 202

    {_stranger_pub, stranger_priv} = ed25519_keypair()
    pending = Repo.get_by!(AnsibleRelay.Db.IdentityAnchor, did: ctx.did, anchor_cid: new_cid)

    resp =
      post_json("/api/v1/identity/anchor/veto", %{
        "did" => ctx.did,
        "pending_anchor_cid" => new_cid,
        "veto_sig" => sign(stranger_priv, pending.canonical_body)
      })

    assert resp.status == 401
  end

  # =========================================================================
  # device attestation — every enrolled device key must be signed by the
  # anchor's identity key (no smuggling unattested device keys)
  # =========================================================================

  test "initial: a device whose attestation_sig is by the identity key is accepted (201)" do
    did = "did:plc:attest_ok_#{System.unique_integer([:positive])}"
    {id_pub, id_priv} = ed25519_keypair()
    {dev_pub, _dev_priv} = ed25519_keypair()

    {anchor, anchor_cid, _body} =
      build_anchor(
        %{
          did: did,
          handle: "attestok.elix.cool",
          identity_key: id_pub,
          reason: "initial",
          devices: [device_record(dev_pub, id_priv)]
        },
        id_priv
      )

    assert post_json("/api/v1/identity/anchor", anchor).status == 201
    assert {:ok, object} = AnchorStore.get_active(did)
    assert object["anchor_cid"] == anchor_cid
    assert [%{"device_key" => ^dev_pub}] = object["devices"]
  end

  test "initial: a device key NOT attested by the identity key is rejected (401)" do
    did = "did:plc:smuggle_#{System.unique_integer([:positive])}"
    {id_pub, id_priv} = ed25519_keypair()
    {dev_pub, _dev_priv} = ed25519_keypair()
    # Attest the device with a DIFFERENT key — a smuggled-in, unattested device.
    {_other_pub, other_priv} = ed25519_keypair()

    {anchor, _cid, _body} =
      build_anchor(
        %{
          did: did,
          handle: "smuggle.elix.cool",
          identity_key: id_pub,
          reason: "initial",
          devices: [device_record(dev_pub, id_priv, attest_priv: other_priv)]
        },
        id_priv
      )

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 401
    assert Jason.decode!(resp.resp_body)["error"] == "invalid_attestation"
    # Nothing was persisted for the DID.
    assert {:error, :not_found} = AnchorStore.get_active(did)
  end

  test "initial: a placeholder (non-signature) attestation_sig is rejected (401)" do
    did = "did:plc:placeholder_#{System.unique_integer([:positive])}"
    {id_pub, id_priv} = ed25519_keypair()
    {dev_pub, _dev_priv} = ed25519_keypair()

    device =
      device_record(dev_pub, id_priv)
      |> Map.put(:attestation_sig, "00")

    {anchor, _cid, _body} =
      build_anchor(
        %{
          did: did,
          handle: "placeholder.elix.cool",
          identity_key: id_pub,
          reason: "initial",
          devices: [device]
        },
        id_priv
      )

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 401
    assert Jason.decode!(resp.resp_body)["error"] == "invalid_attestation"
  end

  test "device_change: re-attesting a device under the same identity key is accepted (200)" do
    # The carried-forward device must be attested by THIS anchor's identity key.
    ctx = seed_initial(with_device: true)

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: ctx.id_pub,
      reason: "device_change",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z",
      devices: [device_record(ctx.dev_pub, ctx.id_priv)]
    }

    {anchor, new_cid, body} = build_anchor(fields, ctx.id_priv)
    anchor = Map.put(anchor, "device_sig", sign(ctx.dev_priv, body))

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 200
    assert Jason.decode!(resp.resp_body)["anchor_cid"] == new_cid
  end

  test "device_change: a device key not attested by the identity key is rejected (401)" do
    ctx = seed_initial(with_device: true)
    {smuggled_pub, _smuggled_priv} = ed25519_keypair()
    {_other_pub, other_priv} = ed25519_keypair()

    fields = %{
      did: ctx.did,
      handle: ctx.handle,
      identity_key: ctx.id_pub,
      reason: "device_change",
      prev_anchor_cid: ctx.anchor_cid,
      created_at: "2026-06-14T09:00:00.000Z",
      # A new device the identity key never signed (attested by a stranger key).
      devices: [
        device_record(ctx.dev_pub, ctx.id_priv),
        device_record(smuggled_pub, ctx.id_priv, attest_priv: other_priv)
      ]
    }

    {anchor, _cid, body} = build_anchor(fields, ctx.id_priv)
    anchor = Map.put(anchor, "device_sig", sign(ctx.dev_priv, body))

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 401
    assert Jason.decode!(resp.resp_body)["error"] == "invalid_attestation"

    # The active anchor is unchanged (the smuggle attempt did not take effect).
    assert {:ok, object} = AnchorStore.get_active(ctx.did)
    assert object["anchor_cid"] == ctx.anchor_cid
  end

  # =========================================================================
  # GET + malformed
  # =========================================================================

  test "GET returns the active anchor cache; 404 when none" do
    ctx = seed_initial()

    resp = get_req("/api/v1/identity/anchor/#{ctx.did}")
    assert resp.status == 200
    object = Jason.decode!(resp.resp_body)
    assert object["did"] == ctx.did
    assert object["state"] == "active"

    resp404 =
      get_req("/api/v1/identity/anchor/did:plc:nobody_#{System.unique_integer([:positive])}")

    assert resp404.status == 404
  end

  test "malformed anchor object is rejected (422)" do
    # Right type, but missing required identity_key.
    resp =
      post_json("/api/v1/identity/anchor", %{
        "type" => @anchor_type,
        "did" => "did:plc:malformed",
        "handle" => "m.elix.cool",
        "reason" => "initial",
        "sig" => "00"
      })

    assert resp.status == 422
    assert Jason.decode!(resp.resp_body)["error"] == "malformed_anchor"
  end

  test "unknown reason is rejected (422)" do
    did = "did:plc:unknown_#{System.unique_integer([:positive])}"
    {id_pub, id_priv} = ed25519_keypair()

    {anchor, _cid, _body} =
      build_anchor(
        %{did: did, handle: "u.elix.cool", identity_key: id_pub, reason: "teleport"},
        id_priv
      )

    resp = post_json("/api/v1/identity/anchor", anchor)
    assert resp.status == 422
    assert Jason.decode!(resp.resp_body)["error"] == "unknown_reason"
  end
end
