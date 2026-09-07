defmodule AnsibleAppview.Authority.Witness do
  @moduledoc """
  Independent durable ordering for public author authority. These tables are
  security state, never disposable projections. Effective revocation/rotation
  occurs when this observer acknowledges it, not at a source-supplied time.
  TLS clients contact their configured observer directly, never a URL in an op.
  """
  alias AnsibleAppview.{Repo, SigVerifier, SigningPayload}
  alias AnsibleAppview.Identity.{AnchorEncoding, ChainVerifier}
  alias AnsibleAppview.Ingest.AuthorVerifier

  def checkpoint(did, chain) when is_binary(did) and is_list(chain) and length(chain) in 1..128 do
    if byte_size(Jason.encode!(chain)) <= 262_144 and ChainVerifier.verified_chain?(did, chain) do
      locked(did, fn ->
        previous = frontier(did)

        cond do
          previous && not prefix?(previous.chain, chain) ->
            {:error, :authority_rollback_or_fork}

          previous && previous.chain == chain ->
            {:ok, %{sequence: previous.sequence, observed_at: previous.observed_at}}

          previous && recovery_guard(did, previous, chain) != :ok ->
            {:error, :recovery_observation_pending}

          true ->
            now = now()
            sequence = if previous, do: previous.sequence + 1, else: 1

            Repo.query!(
              "INSERT INTO authority_frontiers (did, chain, sequence, observed_at) VALUES ($1,$2,$3,$4) ON CONFLICT (did) DO UPDATE SET chain=EXCLUDED.chain, sequence=EXCLUDED.sequence, observed_at=EXCLUDED.observed_at, pending=NULL, pending_since=NULL",
              [did, %{"anchors" => chain}, sequence, now]
            )

            {:ok, %{sequence: sequence, observed_at: now}}
        end
      end)
    else
      {:error, :unbound_author}
    end
  rescue
    _ -> {:error, :invalid_checkpoint}
  end

  def checkpoint(_, _), do: {:error, :invalid_checkpoint}

  def revoke(body, signature, observed_at \\ DateTime.utc_now())

  def revoke(body, signature, observed_at) when is_map(body) and is_binary(signature) do
    did = body["subject_did"]

    with true <- is_binary(did) and byte_size(did) <= 512,
         true <-
           body["type"] == "io.trisaura.identity.webCredentialRevocation" and body["version"] == 1,
         nonce when is_binary(nonce) and byte_size(nonce) in 16..256 <- body["nonce"],
         id when is_binary(id) and byte_size(id) in 1..2048 <- body["credential_id"],
         {:ok, raw_id} <- Base.url_decode64(id, padding: false) do
      locked(did, fn ->
        hash = digest(raw_id)
        # Exact retries stay idempotent even after a subsequent key rotation.
        case Repo.query!(
               "SELECT evidence FROM authority_revocations WHERE did=$1 AND credential_hash=$2",
               [did, hash]
             ).rows do
          [[%{"body" => ^body, "signature" => ^signature}]] ->
            {:ok, %{revoked: true}}

          _ ->
            with %{chain: chain} <- frontier(did),
                 {:ok, at, _} <- DateTime.from_iso8601(body["revoked_at"] || ""),
                 true <- abs(DateTime.diff(observed_at, at)) <= 300,
                 true <- current_signature?(chain, AuthorVerifier.canonical_json(body), signature) do
              Repo.query!(
                "INSERT INTO authority_revocations (did, credential_hash, evidence, observed_at) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING",
                [did, hash, %{"body" => body, "signature" => signature}, observed_at]
              )

              {:ok, %{revoked: true}}
            else
              _ -> {:error, :invalid_revocation_authority}
            end
        end
      end)
    else
      _ -> {:error, :invalid_revocation}
    end
  rescue
    _ -> {:error, :invalid_revocation}
  end

  def revoke(_, _, _), do: {:error, :invalid_revocation}

  def observe(op, payload, observed_at \\ DateTime.utc_now()) do
    did = op["author_did"]
    id = op["op_id"]

    if is_binary(did) and byte_size(did) <= 512 and is_binary(id) and byte_size(id) in 1..512 do
      locked(did, fn ->
        result = observe_locked(op, payload, observed_at)

        case result do
          {:ok, _} ->
            Repo.query!("DELETE FROM authority_pending WHERE did=$1 AND op_id=$2", [did, id])

          {:error, reason}
          when reason in [
                 :authority_checkpoint_required,
                 :unobserved_obsolete_authority,
                 :delegation_not_current
               ] ->
            if is_integer(op["log_id"]) and op["log_id"] > 0 and
                 op["log_id"] <= 9_223_372_036_854_775_807 do
              Repo.query!(
                "INSERT INTO authority_pending (did,op_id,digest,log_id,reason) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (did,op_id) DO NOTHING",
                [did, id, operation_digest(op), op["log_id"], Atom.to_string(reason)]
              )
            end

          _ ->
            :ok
        end

        result
      end)
    else
      {:error, :invalid_operation_identity}
    end
  end

  # A pending entry stores only identifiers/digest, never another content copy.
  # After explicit owner review, the supplied local bytes can retry that exact
  # received log entry without trusting new source metadata or a bulk rebuild.
  def retry_pending(op) do
    case Repo.query!("SELECT log_id,digest FROM authority_pending WHERE did=$1 AND op_id=$2", [
           op["author_did"],
           op["op_id"]
         ]).rows do
      [[log_id, hash]] ->
        if hash == operation_digest(op),
          do: AnsibleAppview.Ingest.Folder.apply_ops([Map.put(op, "log_id", log_id)]),
          else: {0, nil}

      [] ->
        {0, nil}
    end
  end

  # Explicit owner revalidation of exact historical bytes, never a bulk trust
  # exemption for Relay data. This records validation NOW, not a claimed past
  # observation time, and keeps the original author's signature/provenance.
  def revalidate(op, authorization, signature)
      when is_map(op) and is_map(authorization) and is_binary(signature) do
    did = op["author_did"]

    if is_binary(did) and byte_size(did) <= 512 do
      locked(did, fn ->
        with %{chain: chain} <- frontier(did),
             true <-
               authorization["type"] == "io.trisaura.authorizeHistoricalOperation" and
                 authorization["version"] == 1,
             true <- authorization["subject_did"] == did and authorization["op_id"] == op["op_id"],
             true <-
               authorization["observer_origin"] ==
                 Application.fetch_env!(:ansible_appview, :authority_origin),
             hash <- operation_digest(op),
             true <- authorization["operation_digest"] == hash,
             nonce when is_binary(nonce) and byte_size(nonce) in 16..256 <- authorization["nonce"],
             {:ok, at, _} <- DateTime.from_iso8601(authorization["issued_at"] || ""),
             true <- abs(DateTime.diff(now(), at)) <= 300,
             true <-
               current_signature?(chain, AuthorVerifier.canonical_json(authorization), signature),
             {:ok, raw} <- Base.decode64(op["payload"]),
             {:ok, payload} when is_map(payload) <- Jason.decode(raw),
             true <- payload["visibility"] in ["public", "unlisted"],
             current_op <- authoritative_op(op, chain, now()),
             {:ok, _} <- AuthorVerifier.verify(current_op, payload),
             bound <- AuthorVerifier.bind_provenance(current_op, payload),
             bound <- current_canonical_author(bound, current_op, chain) do
          authority =
            Map.take(
              bound,
              ~w(identity_chain public_key_hex signing_algorithm canonical_author_did anchor_expires_at)
            )
            |> Map.put("observation_kind", "owner_revalidated")
            |> Map.put("revalidation", %{
              "authorization" => authorization,
              "signature" => signature
            })

          case Repo.query!(
                 "SELECT digest FROM authority_observations WHERE did=$1 AND op_id=$2",
                 [did, op["op_id"]]
               ).rows do
            [[^hash]] ->
              {:ok, %{revalidated: true}}

            [[_]] ->
              {:error, :conflicting_observed_operation}

            [] ->
              Repo.query!(
                "INSERT INTO authority_observations (did, op_id, digest, authority, observed_at) VALUES ($1,$2,$3,$4,$5)",
                [did, op["op_id"], hash, authority, now()]
              )

              {:ok, %{revalidated: true}}
          end
        else
          _ -> {:error, :invalid_historical_authorization}
        end
      end)
    else
      {:error, :invalid_historical_authorization}
    end
  rescue
    _ -> {:error, :invalid_historical_authorization}
  end

  def revalidate(_, _, _), do: {:error, :invalid_historical_authorization}

  def operation_digest(op),
    do: digest(SigningPayload.build(op) <> "\0" <> (op["signature"] || ""))

  defp observe_locked(op, payload, observed_at) do
    did = op["author_did"]
    hash = operation_digest(op)

    case Repo.query!(
           "SELECT digest, authority FROM authority_observations WHERE did=$1 AND op_id=$2",
           [did, op["op_id"]]
         ).rows do
      [[^hash, authority]] ->
        {:ok, Map.merge(op, authority)}

      [[_, _]] ->
        {:error, :conflicting_observed_operation}

      [] ->
        with {:ok, _} <- AuthorVerifier.verify(op, payload),
             %{chain: chain} <- frontier(did),
             current_op <- authoritative_op(op, chain, observed_at),
             {:ok, _} <- AuthorVerifier.verify(current_op, payload),
             :ok <- current_authority(current_op, payload, chain, observed_at),
             bound <- AuthorVerifier.bind_provenance(current_op, payload),
             bound <- current_canonical_author(bound, current_op, chain) do
          authority =
            Map.take(
              bound,
              ~w(identity_chain public_key_hex signing_algorithm canonical_author_did anchor_expires_at)
            )

          Repo.query!(
            "INSERT INTO authority_observations (did, op_id, digest, authority, observed_at) VALUES ($1,$2,$3,$4,$5)",
            [did, op["op_id"], hash, authority, observed_at]
          )

          {:ok, bound}
        else
          nil -> {:error, :authority_checkpoint_required}
          {:error, _} = error -> error
        end
    end
  end

  defp current_authority(op, payload, chain, observed_at) do
    case payload["web_author_proof"] do
      %{"delegation" => delegation} = proof ->
        with true <-
               current_signature?(
                 chain,
                 AuthorVerifier.canonical_json(delegation),
                 proof["delegation_signature"]
               ),
             {:ok, issued, _} <- DateTime.from_iso8601(delegation["issued_at"]),
             {:ok, expires, _} <- DateTime.from_iso8601(delegation["expires_at"]),
             true <-
               DateTime.compare(observed_at, issued) != :lt and
                 DateTime.compare(observed_at, expires) == :lt,
             %{rows: []} <-
               Repo.query!(
                 "SELECT 1 FROM authority_revocations WHERE did=$1 AND credential_hash=$2",
                 [op["author_did"], delegation["credential_id_hash"]]
               ) do
          :ok
        else
          _ -> {:error, :delegation_not_current}
        end

      _ ->
        if current_signature?(chain, SigningPayload.build(op), op["signature"]),
          do: :ok,
          else: {:error, :unobserved_obsolete_authority}
    end
  end

  # A never-observed migration cannot borrow an obsolete root key merely by
  # backdating its created_at field. Recorded operations keep their prior
  # verified projection; new alias projections require current dual authority.
  defp current_canonical_author(bound, op, chain) do
    canonical = bound["canonical_author_did"]

    if canonical == op["author_did"] do
      bound
    else
      with evidence when is_map(evidence) <- op["identity_migration"],
           %{chain: target_chain} <- frontier(canonical, true),
           body <- AuthorVerifier.migration_body(evidence),
           true <- current_signature?(chain, body, evidence["legacy_sig"]),
           true <- current_signature?(target_chain, body, evidence["v1_sig"]) do
        bound
      else
        _ -> Map.put(bound, "canonical_author_did", op["author_did"])
      end
    end
  end

  defp authoritative_op(op, chain, _at) do
    op = Map.put(op, "anchor_expires_at", DateTime.to_iso8601(DateTime.add(now(), 300)))

    if String.starts_with?(op["author_did"], "did:key:"),
      do: Map.delete(op, "identity_chain"),
      else: Map.put(op, "identity_chain", chain)
  end

  # An untrusted Relay cannot bypass the device-recovery grace by backdating
  # the candidate. The observer starts its own 72-hour clock on first sight.
  defp recovery_guard(did, previous, chain) do
    successors = Enum.drop(chain, length(previous.chain))
    recovery = Enum.find(successors, &(&1["reason"] == "recovery"))

    if recovery do
      cid = AnchorEncoding.compute_cid(recovery)

      revoked =
        Repo.query!("SELECT 1 FROM authority_revocations WHERE did=$1 AND credential_hash=$2", [
          did,
          "anchor:" <> cid
        ]).rows != []

      cond do
        revoked ->
          :pending

        Enum.count(successors, &(&1["reason"] == "recovery")) > 1 ->
          :pending

        previous.pending && previous.pending["cid"] == cid ->
          since = DateTime.from_naive!(previous.pending_since, "Etc/UTC")
          if DateTime.diff(now(), since) >= 259_200, do: :ok, else: :pending

        true ->
          Repo.query!(
            "UPDATE authority_frontiers SET pending=$2, pending_since=$3 WHERE did=$1",
            [did, %{"cid" => cid, "anchor" => recovery}, now()]
          )

          :pending
      end
    else
      :ok
    end
  end

  def veto(did, cid, signature, canonical_body \\ nil)

  def veto(did, cid, signature, canonical_body)
      when is_binary(did) and is_binary(cid) and is_binary(signature) do
    locked(did, fn ->
      with %{chain: chain} = state <- frontier(did),
           body when is_binary(body) <-
             canonical_body ||
               (Map.get(state, :pending) && AnchorEncoding.canonical_body(state.pending["anchor"])),
           true <- byte_size(body) <= 262_144 and AnchorEncoding.cid_of_body(body) == cid,
           active <- List.last(chain),
           true <-
             current_signature?(chain, body, signature) or
               Enum.any?(active["devices"] || [], fn device ->
                 SigVerifier.verify_ed25519(device["device_key"], body, signature)
               end) do
        Repo.query!(
          "INSERT INTO authority_revocations (did, credential_hash, evidence, observed_at) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING",
          [did, "anchor:" <> cid, %{"veto_sig" => signature}, now()]
        )

        {:ok, %{vetoed: true}}
      else
        _ -> {:error, :invalid_veto}
      end
    end)
  end

  def veto(_, _, _, _), do: {:error, :invalid_veto}

  defp current_signature?(chain, bytes, signature) do
    anchor = List.last(chain)

    SigVerifier.verify_identity(
      anchor["identity_key_algorithm"] || "ed25519",
      anchor["identity_key"],
      bytes,
      signature
    )
  end

  defp prefix?(old, new) do
    length(new) >= length(old) and
      Enum.all?(Enum.zip(old, new), fn {a, b} ->
        AnchorEncoding.compute_cid(a) == AnchorEncoding.compute_cid(b)
      end)
  end

  defp frontier(did, protect_transition \\ false) do
    case Repo.query!(
           "SELECT chain, sequence, observed_at, pending, pending_since FROM authority_frontiers WHERE did=$1" <>
             if(protect_transition, do: " FOR SHARE", else: ""),
           [did]
         ).rows do
      [[%{"anchors" => chain}, sequence, at, pending, since]] ->
        %{
          chain: chain,
          sequence: sequence,
          observed_at: at,
          pending: pending,
          pending_since: since
        }

      [] ->
        case AuthorVerifier.authority_keys(%{"author_did" => did}) do
          {:ok, [{algorithm, key}]} ->
            %{
              chain: [%{"identity_key_algorithm" => algorithm, "identity_key" => key}],
              sequence: 0
            }

          _ ->
            nil
        end
    end
  end

  defp locked(did, fun) do
    case Repo.transaction(fn ->
           Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
             "elix.authority.v1:" <> did
           ])

           fun.()
         end) do
      {:ok, result} -> result
      {:error, _} -> {:error, :authority_store_unavailable}
    end
  end

  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp now, do: DateTime.utc_now()
end
