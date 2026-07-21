defmodule AnsibleRelay.WebauthnSync do
  @moduledoc "Persistent WebAuthn ceremonies and short-lived sync capabilities."

  import Ecto.Query
  alias AnsibleRelay.{IdentityCache, Repo, SigVerifier}
  alias AnsibleRelay.Db.{WebauthnChallenge, WebauthnCredential}

  @challenge_ttl 120
  @capability_ttl 300
  @scope "sync:write"

  def registration_options(did) do
    with :ok <- anchored_did(did) do
      challenge = new_challenge(:registration, [])
      row = persist_challenge(did, "registration", challenge)

      {:ok,
       %{
         "challenge_id" => row.challenge_id,
         "publicKey" => %{
           "challenge" => b64(challenge.bytes),
           "rp" => %{"id" => rp_id(), "name" => "Elix"},
           "user" => %{
             "id" => b64(:crypto.hash(:sha256, did)),
             "name" => did,
             "displayName" => did
           },
           "pubKeyCredParams" => [%{"type" => "public-key", "alg" => -7}],
           "timeout" => @challenge_ttl * 1000,
           "attestation" => "none",
           "authenticatorSelection" => %{
             "residentKey" => "required",
             "requireResidentKey" => true,
             "userVerification" => "required"
           },
           "excludeCredentials" => credential_descriptors(did)
         }
       }}
    end
  end

  def finish_registration(did, challenge_id, credential, did_signature) do
    with {:ok, challenge} <- take_challenge(challenge_id, did, "registration"),
         {:ok, raw_id} <- decode64(credential["rawId"] || credential["id"]),
         :ok <- verify_enrollment_did_proof(did, challenge_id, raw_id, did_signature),
         {:ok, client_data} <- decode64(get_in(credential, ["response", "clientDataJSON"])),
         {:ok, attestation} <- decode64(get_in(credential, ["response", "attestationObject"])),
         {:ok, {auth_data, _attestation_result}} <-
           Wax.register(attestation, client_data, challenge),
         attested <- auth_data.attested_credential_data,
         true <- attested.credential_id == raw_id,
         {:ok, saved} <- save_credential(did, attested, credential) do
      {:ok, saved}
    else
      false -> {:error, :credential_id_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :invalid_registration}
    end
  end

  def authentication_options(did, @scope) do
    credentials = list_credentials(did)

    with :ok <- anchored_did(did),
         false <- credentials == [] do
      allow = Enum.map(credentials, &{Base.encode64(&1.credential_id), decode_term(&1.cose_key)})
      challenge = new_challenge(:authentication, allow)
      row = persist_challenge(did, "authentication", challenge)

      {:ok,
       %{
         "challenge_id" => row.challenge_id,
         "publicKey" => %{
           "challenge" => b64(challenge.bytes),
           "rpId" => rp_id(),
           "timeout" => @challenge_ttl * 1000,
           "userVerification" => "required",
           "allowCredentials" => credential_descriptors(did)
         }
       }}
    else
      true -> {:error, :not_enrolled}
      {:error, _} = error -> error
    end
  end

  def authentication_options(_did, _scope), do: {:error, :invalid_scope}

  def finish_authentication(did, challenge_id, credential, @scope) do
    with {:ok, challenge} <- take_challenge(challenge_id, did, "authentication"),
         {:ok, credential_id} <- decode64(credential["rawId"] || credential["id"]),
         %WebauthnCredential{did: ^did} = stored <- Repo.get(WebauthnCredential, credential_id),
         {:ok, client_data} <- decode64(get_in(credential, ["response", "clientDataJSON"])),
         {:ok, auth_data} <- decode64(get_in(credential, ["response", "authenticatorData"])),
         {:ok, signature} <- decode64(get_in(credential, ["response", "signature"])),
         {:ok, verified} <-
           Wax.authenticate(
             Base.encode64(credential_id),
             auth_data,
             signature,
             client_data,
             challenge,
             [{Base.encode64(credential_id), decode_term(stored.cose_key)}]
           ),
         :ok <- validate_sign_count(stored.sign_count, verified.sign_count) do
      update_sign_count(stored, verified.sign_count)
      {:ok, issue_capability(did, [@scope])}
    else
      nil -> {:error, :unknown_credential}
      {:error, _} = error -> error
      _ -> {:error, :invalid_assertion}
    end
  end

  def finish_authentication(_did, _challenge_id, _credential, _scope),
    do: {:error, :invalid_scope}

  def authorize(conn, expected_did, required_scope \\ @scope) do
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, claims} <- verify_capability(token),
         true <- claims["sub"] == expected_did,
         true <- claims["aud"] == audience(),
         true <- required_scope in claims["scp"] do
      :ok
    else
      _ -> {:error, :invalid_sync_capability}
    end
  end

  def enforcement_enabled? do
    Application.get_env(:ansible_relay, :webauthn_sync_capability_required, false)
  end

  defp new_challenge(kind, allow) do
    options = [
      origin: origin(),
      rp_id: rp_id(),
      timeout: @challenge_ttl,
      user_verification: "required",
      verify_trust_root: false
    ]

    if kind == :registration do
      Wax.new_registration_challenge(options)
    else
      Wax.new_authentication_challenge(Keyword.put(options, :allow_credentials, allow))
    end
  end

  defp persist_challenge(did, kind, challenge) do
    attrs = %{
      challenge_id: token("wac"),
      did: did,
      kind: kind,
      scope: @scope,
      wax_challenge: :erlang.term_to_binary(challenge),
      expires_at: DateTime.add(DateTime.utc_now(), @challenge_ttl, :second)
    }

    %WebauthnChallenge{} |> WebauthnChallenge.changeset(attrs) |> Repo.insert!()
  end

  # Claim the challenge while holding a row lock, then commit the consumed
  # marker before any expensive cryptographic verification. A failed ceremony
  # intentionally burns the challenge; clients must request a fresh one.
  defp take_challenge(id, did, kind) do
    Repo.transaction(fn ->
      row =
        Repo.one(
          from(c in WebauthnChallenge,
            where: c.challenge_id == ^id,
            lock: "FOR UPDATE"
          )
        )

      case row do
        %WebauthnChallenge{did: ^did, kind: ^kind, consumed_at: nil} = challenge_row ->
          if DateTime.compare(challenge_row.expires_at, DateTime.utc_now()) == :gt do
            challenge_row
            |> Ecto.Changeset.change(consumed_at: DateTime.utc_now())
            |> Repo.update!()

            decode_term(challenge_row.wax_challenge)
          else
            Repo.rollback(:expired_challenge)
          end

        _ ->
          Repo.rollback(:invalid_challenge)
      end
    end)
  end

  defp save_credential(did, attested, response) do
    attrs = %{
      credential_id: attested.credential_id,
      did: did,
      cose_key: :erlang.term_to_binary(attested.credential_public_key),
      transports: get_in(response, ["response", "transports"]) || [],
      sign_count: 0
    }

    case Repo.get(WebauthnCredential, attested.credential_id) do
      nil ->
        %WebauthnCredential{}
        |> WebauthnCredential.changeset(attrs)
        |> Repo.insert()

      %WebauthnCredential{did: ^did} = existing ->
        {:ok, existing}

      %WebauthnCredential{} ->
        {:error, :credential_already_bound}
    end
  end

  defp list_credentials(did) do
    Repo.all(from(c in WebauthnCredential, where: c.did == ^did))
  end

  defp credential_descriptors(did) do
    Enum.map(list_credentials(did), fn credential ->
      %{
        "type" => "public-key",
        "id" => b64(credential.credential_id),
        "transports" => credential.transports
      }
    end)
  end

  defp verify_enrollment_did_proof(did, challenge_id, credential_id, signature) do
    public_key = IdentityCache.public_key_hex(did)
    message = challenge_id <> "." <> b64(credential_id)

    if is_binary(public_key) and SigVerifier.verify_ed25519(public_key, message, signature),
      do: :ok,
      else: {:error, :invalid_did_proof}
  end

  defp anchored_did(did) do
    if IdentityCache.verified?(did), do: :ok, else: {:error, :unverified_did}
  end

  defp validate_sign_count(old, new) when old > 0 and new > 0 and new <= old,
    do: {:error, :sign_count_replay}

  defp validate_sign_count(_old, _new), do: :ok

  defp update_sign_count(row, count) do
    row
    |> Ecto.Changeset.change(sign_count: count, last_used_at: DateTime.utc_now())
    |> Repo.update!()
  end

  defp issue_capability(did, scopes) do
    now = System.system_time(:second)

    claims = %{
      "jti" => token("sc"),
      "sub" => did,
      "aud" => audience(),
      "scp" => scopes,
      "iat" => now,
      "exp" => now + @capability_ttl
    }

    payload = claims |> Jason.encode!() |> b64()
    signature = :crypto.mac(:hmac, :sha256, capability_secret(), payload) |> b64()
    token = payload <> "." <> signature
    %{token: token, token_type: "Bearer", expires_in: @capability_ttl, scope: scopes}
  end

  defp verify_capability(token) do
    with [payload, signature] <- String.split(token, ".", parts: 2),
         expected <- :crypto.mac(:hmac, :sha256, capability_secret(), payload) |> b64(),
         true <- Plug.Crypto.secure_compare(signature, expected),
         {:ok, raw} <- decode64(payload),
         {:ok, claims} <- Jason.decode(raw),
         true <- is_integer(claims["exp"]) and claims["exp"] > System.system_time(:second) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_capability}
    end
  end

  defp capability_secret do
    Application.fetch_env!(:ansible_relay, :sync_capability_secret)
  end

  defp rp_id, do: Application.get_env(:ansible_relay, :webauthn_rp_id, "elix.cool")
  defp origin, do: Application.get_env(:ansible_relay, :webauthn_origin, "https://elix.cool")
  defp audience, do: Application.get_env(:ansible_relay, :relay_origin, origin())
  defp token(prefix), do: prefix <> "_" <> (:crypto.strong_rand_bytes(24) |> b64())
  defp b64(binary), do: Base.url_encode64(binary, padding: false)
  defp decode64(value) when is_binary(value), do: Base.url_decode64(value, padding: false)
  defp decode64(_), do: :error
  defp decode_term(binary), do: :erlang.binary_to_term(binary, [:safe])
end
