defmodule AnsibleRelay.Web.Controllers.IdentityV2Controller do
  @moduledoc """
  V2.0 Passkeys Identity registration endpoints.

  POST /api/v2/identity/register — begin registration, issue nonce
  POST /api/v2/identity/anchor  — verify Ed25519 sig and anchor DID
  """

  alias AnsibleRelay.{DidAccountCache, DidElix, IdentityCache, IdentityWritePolicy, SigVerifier}

  def register(conn, params) do
    with {:ok, public_key_hex} <- require_field(params, "public_key_hex"),
         {:ok, handle_suffix} <- require_field(params, "handle_suffix"),
         signing_algorithm = Map.get(params, "signing_algorithm", "ed25519"),
         :ok <- IdentityWritePolicy.validate(signing_algorithm),
         :ok <- validate_public_key(signing_algorithm, public_key_hex),
         :ok <- validate_handle_suffix(handle_suffix) do
      handle = "#{handle_suffix}.#{handle_domain()}"

      case DidAccountCache.get_by_handle(handle) do
        {:ok, did} ->
          # Re-registration is intentionally idempotent for the same
          # hardware-held identity key.  A reinstall can retain the key while
          # local app state is cleared; issuing a fresh nonce lets the client
          # restore the verified-DID cache without claiming another handle.
          case DidAccountCache.get(did) do
            {:ok, entry}
            when entry.public_key_hex == public_key_hex and
                   entry.signing_algorithm == signing_algorithm ->
              issue_registration_nonce(conn, public_key_hex, handle)

            _ ->
              send_json(conn, 409, %{error: "handle_taken"})
          end

        :not_found ->
          issue_registration_nonce(conn, public_key_hex, handle)
      end
    else
      {:error, {:missing_field, field}} ->
        send_json(conn, 422, %{error: "missing_fields", field: field})

      {:error, :invalid_public_key_hex} ->
        send_json(conn, 422, %{
          error: "missing_fields",
          detail: "public_key_hex does not match signing_algorithm"
        })

      {:error, :unsupported_signing_algorithm} ->
        send_json(conn, 422, %{
          error: "unsupported_signing_algorithm",
          expected: IdentityWritePolicy.expected()
        })

      {:error, :invalid_handle_suffix} ->
        send_json(conn, 422, %{
          error: "missing_fields",
          detail: "handle_suffix must be alphanumeric"
        })
    end
  end

  def anchor(conn, params) do
    with {:ok, did} <- require_field(params, "did"),
         {:ok, public_key_hex} <- require_field(params, "public_key_hex"),
         {:ok, handle} <- require_field(params, "handle"),
         {:ok, registration_sig} <- require_field(params, "registration_sig"),
         {:ok, nonce} <- require_field(params, "nonce"),
         signing_algorithm = Map.get(params, "signing_algorithm", "ed25519"),
         genesis_commitment = Map.get(params, "genesis_commitment"),
         :ok <- IdentityWritePolicy.validate(signing_algorithm),
         :ok <- validate_did(did),
         :ok <- validate_public_key(signing_algorithm, public_key_hex),
         :ok <- validate_handle(handle),
         :ok <- validate_registration_binding(did, public_key_hex, genesis_commitment),
         proof = registration_proof(nonce, did, genesis_commitment) do
      # Verify signature BEFORE consuming the nonce so an invalid sig does not
      # burn the nonce — the client can retry without requesting a new one.
      if not valid_registration_signature?(
           signing_algorithm,
           public_key_hex,
           proof,
           registration_sig
         ) do
        send_json(conn, 401, %{error: "invalid_sig"})
      else
        case DidAccountCache.consume_nonce(public_key_hex, nonce, handle) do
          :ok ->
            anchor_verified_did(conn, did, public_key_hex, signing_algorithm, handle)

          {:error, :handle_mismatch} ->
            send_json(conn, 401, %{error: "handle_mismatch"})

          {:error, :expired_nonce} ->
            send_json(conn, 401, %{error: "expired_nonce"})

          {:error, :invalid_nonce} ->
            send_json(conn, 401, %{error: "invalid_nonce"})
        end
      end
    else
      {:error, {:missing_field, field}} ->
        send_json(conn, 422, %{error: "missing_fields", field: field})

      {:error, :invalid_did} ->
        send_json(conn, 422, %{error: "invalid_did"})

      {:error, :invalid_public_key_hex} ->
        send_json(conn, 422, %{error: "invalid_public_key"})

      {:error, :unsupported_signing_algorithm} ->
        send_json(conn, 422, %{
          error: "unsupported_signing_algorithm",
          expected: IdentityWritePolicy.expected()
        })

      {:error, :invalid_handle} ->
        send_json(conn, 422, %{error: "invalid_handle"})

      {:error, :invalid_genesis_commitment} ->
        send_json(conn, 422, %{error: "invalid_genesis_commitment"})

      {:error, :did_mismatch} ->
        send_json(conn, 422, %{error: "did_mismatch"})
    end
  end

  @doc "Rotate an existing DID to a new hardware-held verification key."
  def rotate_key(conn, params) do
    with {:ok, did} <- require_field(params, "did"),
         {:ok, new_public_key_hex} <- require_field(params, "new_public_key_hex"),
         {:ok, new_algorithm} <- require_field(params, "new_signing_algorithm"),
         {:ok, old_signature} <- require_field(params, "old_signature"),
         {:ok, new_signature} <- require_field(params, "new_signature"),
         {:ok, issued_at} <- require_field(params, "issued_at"),
         expected_version when is_integer(expected_version) <- params["expected_key_version"],
         "hardware" <- params["new_custody"],
         :ok <- IdentityWritePolicy.validate(new_algorithm),
         :ok <- validate_public_key(new_algorithm, new_public_key_hex),
         :ok <- validate_rotation_time(issued_at),
         {:ok, current} <- DidAccountCache.get(did),
         true <- Map.get(current, :key_version, 1) == expected_version,
         payload = rotation_payload(params),
         true <-
           SigVerifier.verify_identity(
             Map.get(current, :signing_algorithm, "ed25519"),
             current.public_key_hex,
             payload,
             old_signature
           ),
         true <-
           SigVerifier.verify_identity(
             new_algorithm,
             new_public_key_hex,
             payload,
             new_signature
           ),
         {:ok, updated} <-
           DidAccountCache.rotate_key(
             did,
             expected_version,
             new_public_key_hex,
             new_algorithm
           ) do
      send_json(conn, 200, %{
        did: did,
        signing_algorithm: updated.signing_algorithm,
        public_key_hex: updated.public_key_hex,
        key_version: updated.key_version,
        custody: "hardware"
      })
    else
      :not_found ->
        send_json(conn, 404, %{error: "did_not_found"})

      {:error, :stale_key_version} ->
        send_json(conn, 409, %{error: "stale_key_version"})

      {:error, :invalid_rotation_time} ->
        send_json(conn, 422, %{error: "invalid_rotation_time"})

      {:error, :invalid_public_key_hex} ->
        send_json(conn, 422, %{error: "invalid_public_key"})

      {:error, :unsupported_signing_algorithm} ->
        send_json(conn, 422, %{
          error: "unsupported_signing_algorithm",
          expected: IdentityWritePolicy.expected()
        })

      {:error, :unavailable} ->
        send_json(conn, 503, %{error: "verification_unavailable", retryable: true})

      {:error, {:missing_field, field}} ->
        send_json(conn, 422, %{error: "missing_fields", field: field})

      _ ->
        send_json(conn, 401, %{error: "invalid_key_rotation"})
    end
  end

  def rotation_payload(params) do
    fields = [
      {"did", params["did"]},
      {"expected_key_version", params["expected_key_version"]},
      {"issued_at", params["issued_at"]},
      {"new_custody", params["new_custody"]},
      {"new_public_key_hex", params["new_public_key_hex"]},
      {"new_signing_algorithm", params["new_signing_algorithm"]},
      {"type", "io.trisaura.identity.keyRotation"},
      {"version", 1}
    ]

    "{" <>
      Enum.map_join(fields, ",", fn {key, value} ->
        Jason.encode!(key) <> ":" <> Jason.encode!(value)
      end) <> "}"
  end

  # --- Helpers ---

  defp anchor_verified_did(conn, did, public_key_hex, signing_algorithm, handle) do
    case {DidAccountCache.get(did), DidAccountCache.get_by_handle(handle)} do
      {{:ok, entry}, {:ok, ^did}} ->
        # This is a retry of the same self-custodied identity.  Refresh the
        # verified-DID cache (which backs sync capabilities) instead of
        # turning a harmless reinstall retry into an unverified DID.
        if entry.public_key_hex == public_key_hex and
             entry.signing_algorithm == signing_algorithm do
          :ok = IdentityCache.put(did, public_key_hex, "v2:#{did}", nil, signing_algorithm)

          send_json(conn, 200, %{
            did: did,
            handle: handle,
            expires_at: DateTime.to_iso8601(entry.expires_at)
          })
        else
          send_json(conn, 409, %{error: "duplicate_did"})
        end

      {{:ok, _entry}, _} ->
        send_json(conn, 409, %{error: "duplicate_did"})

      {:not_found, {:ok, existing_did}} when existing_did != did ->
        send_json(conn, 409, %{error: "handle_taken"})

      {:not_found, _} ->
        :ok =
          DidAccountCache.put(did, public_key_hex, handle, signing_algorithm: signing_algorithm)

        :ok = IdentityCache.put(did, public_key_hex, "v2:#{did}", nil, signing_algorithm)
        {:ok, entry} = DidAccountCache.get(did)

        send_json(conn, 200, %{
          did: did,
          handle: handle,
          expires_at: DateTime.to_iso8601(entry.expires_at)
        })

      # A DB outage during the uniqueness lookup must not be mistaken for a
      # free/duplicate slot — 503 (retryable) rather than a wrong 409/200.
      {{:error, :unavailable}, _} ->
        send_json(conn, 503, %{error: "verification_unavailable", retryable: true})
    end
  end

  defp issue_registration_nonce(conn, public_key_hex, handle) do
    case DidAccountCache.issue_nonce(public_key_hex, handle) do
      {:ok, %{nonce: nonce, expires_at: expires_at}} ->
        send_json(conn, 200, %{
          nonce: nonce,
          expires_at: DateTime.to_iso8601(expires_at),
          handle: handle
        })

      {:error, :handle_pending} ->
        send_json(conn, 409, %{error: "handle_pending"})
    end
  end

  defp require_field(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing_field, key}}
      "" -> {:error, {:missing_field, key}}
      val -> {:ok, val}
    end
  end

  defp validate_public_key_hex(hex) when is_binary(hex) do
    if String.length(hex) == 64 and String.match?(hex, ~r/\A[0-9a-fA-F]+\z/) do
      :ok
    else
      {:error, :invalid_public_key_hex}
    end
  end

  defp validate_public_key_hex(_), do: {:error, :invalid_public_key_hex}

  defp validate_public_key("ed25519", public_key_hex), do: validate_public_key_hex(public_key_hex)

  defp validate_public_key("p256-sha256", <<"04", rest::binary>> = public_key_hex) do
    if byte_size(rest) == 128 and String.match?(public_key_hex, ~r/\A[0-9a-fA-F]+\z/) do
      :ok
    else
      {:error, :invalid_public_key_hex}
    end
  end

  defp validate_public_key(_, _), do: {:error, :invalid_public_key_hex}

  defp validate_handle_suffix(suffix) when is_binary(suffix) do
    # DNS label rules: 1–63 chars, alphanumeric or internal hyphens,
    # must start and end with alphanumeric.
    if String.match?(suffix, ~r/\A[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/) do
      :ok
    else
      {:error, :invalid_handle_suffix}
    end
  end

  defp validate_handle_suffix(_), do: {:error, :invalid_handle_suffix}

  # Canonical user identity is `did:elix` (layered identity, 2026-06-16).
  # `did:plc` is still accepted so an opt-in Bluesky-bridge alias can anchor;
  # both use a base32 (`[a-z2-7]`) suffix.
  defp validate_did(did) when is_binary(did) do
    if String.match?(did, ~r/\Adid:(elix|plc):[a-z2-7]{10,}\z/) do
      :ok
    else
      {:error, :invalid_did}
    end
  end

  defp validate_did(_), do: {:error, :invalid_did}

  defp validate_registration_binding(did, _public_key_hex, nil) do
    if String.match?(did, ~r/\Adid:elix:z[a-z2-7]{52}\z/),
      do: {:error, :invalid_genesis_commitment},
      else: :ok
  end

  defp validate_registration_binding(did, public_key_hex, commitment)
       when is_map(commitment) do
    with :ok <- DidElix.validate_v1_commitment(commitment),
         ^public_key_hex <- commitment["genesis_key"],
         true <- DidElix.matches_v1?(did, commitment) do
      :ok
    else
      false -> {:error, :did_mismatch}
      nil -> {:error, :invalid_genesis_commitment}
      {:error, _} = error -> error
      _ -> {:error, :invalid_genesis_commitment}
    end
  end

  defp validate_registration_binding(_did, _public_key_hex, _commitment),
    do: {:error, :invalid_genesis_commitment}

  defp registration_proof(nonce, _did, nil), do: nonce

  defp registration_proof(nonce, did, commitment),
    do: DidElix.registration_payload(nonce, did, commitment)

  defp validate_handle(handle) when is_binary(handle) do
    domain = handle_domain()

    if String.ends_with?(String.downcase(handle), ".#{domain}") and
         validate_handle_suffix(
           String.slice(handle, 0, byte_size(handle) - byte_size(domain) - 1)
         ) == :ok do
      :ok
    else
      {:error, :invalid_handle}
    end
  end

  defp validate_handle(_), do: {:error, :invalid_handle}

  defp handle_domain do
    Application.get_env(:ansible_relay, :identity_handle_domain, "elix.cool")
    |> String.trim()
    |> String.downcase()
  end

  defp validate_rotation_time(value) when is_binary(value) do
    with {:ok, issued_at, 0} <- DateTime.from_iso8601(value),
         seconds <- abs(DateTime.diff(DateTime.utc_now(), issued_at, :second)),
         true <- seconds <= 300 do
      :ok
    else
      _ -> {:error, :invalid_rotation_time}
    end
  end

  defp validate_rotation_time(_), do: {:error, :invalid_rotation_time}

  defp valid_registration_signature?(algorithm, public_key_hex, nonce, registration_sig) do
    accepts_dev_signature? =
      Application.get_env(:ansible_relay, :allow_dev_identity_signatures, false) &&
        String.starts_with?(registration_sig, "dev-sig-")

    accepts_dev_signature? ||
      SigVerifier.verify_identity(algorithm, public_key_hex, nonce, registration_sig)
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
