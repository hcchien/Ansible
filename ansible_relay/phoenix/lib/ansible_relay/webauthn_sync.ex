defmodule AnsibleRelay.WebauthnSync do
  @moduledoc "Persistent WebAuthn ceremonies and short-lived sync capabilities."

  import Ecto.Query
  alias AnsibleRelay.{IdentityCache, IdentityWritePolicy, Repo}
  alias AnsibleRelay.Db.{WebauthnChallenge, WebauthnCredential}

  @challenge_ttl 120
  @capability_ttl 300
  @scope "sync:write"
  @publication_actions ~w(
    forum.publish forum.reply forum.edit forum.delete forum.react forum.moderate
  )

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

  def finish_registration(did, challenge_id, credential, did_signature, delegation \\ nil) do
    with {:ok, challenge} <- take_challenge(challenge_id, did, "registration"),
         {:ok, raw_id} <- decode64(credential["rawId"] || credential["id"]),
         {:ok, delegation_attrs} <-
           verify_enrollment_did_proof(
             did,
             challenge_id,
             raw_id,
             did_signature,
             delegation
           ),
         {:ok, client_data} <- decode64(get_in(credential, ["response", "clientDataJSON"])),
         {:ok, attestation} <- decode64(get_in(credential, ["response", "attestationObject"])),
         {:ok, {auth_data, _attestation_result}} <-
           Wax.register(attestation, client_data, challenge),
         attested <- auth_data.attested_credential_data,
         true <- attested.credential_id == raw_id,
         {:ok, saved} <-
           save_credential(
             did,
             attested,
             credential,
             did_signature,
             delegation_attrs
           ) do
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

  def publication_options(did, session_id, operation, operation_hash)
      when is_binary(session_id) and is_map(operation) and is_binary(operation_hash) do
    action = operation["action"]
    credentials = active_publication_credentials(did, action)

    with :ok <- anchored_did(did),
         false <- credentials == [] do
      allow =
        Enum.map(credentials, &{Base.encode64(&1.credential_id), decode_term(&1.cose_key)})

      challenge = new_challenge(:authentication, allow)

      row =
        persist_challenge(did, "web_publication", challenge,
          scope: action,
          session_id: session_id,
          operation_id: operation["operation_id"],
          operation_hash: operation_hash,
          binding: %{
            "action" => action,
            "target_forum_host" => operation["target_forum_host"],
            "board_id" => operation["board_id"]
          }
        )

      {:ok,
       %{
         "challenge_id" => row.challenge_id,
         "operation_id" => row.operation_id,
         "operation_hash" => row.operation_hash,
         "expires_at" => DateTime.to_iso8601(row.expires_at),
         "publicKey" => %{
           "challenge" => b64(challenge.bytes),
           "rpId" => rp_id(),
           "timeout" => @challenge_ttl * 1000,
           "userVerification" => "required",
           "allowCredentials" => credential_descriptors(credentials)
         }
       }}
    else
      true -> {:error, :not_enrolled}
      {:error, _} = error -> error
    end
  end

  def publication_options(_did, _session_id, _operation, _operation_hash),
    do: {:error, :invalid_operation}

  def verify_publication(
        did,
        session_id,
        challenge_id,
        operation,
        operation_hash,
        credential
      ) do
    action = operation["action"]

    with {:ok, challenge_row, challenge} <-
           take_publication_challenge(challenge_id, did, session_id),
         true <- IdentityWritePolicy.allowed_author_proof?("webauthn-p256-sha256"),
         true <- challenge_row.operation_id == operation["operation_id"],
         true <- challenge_row.operation_hash == operation_hash,
         true <- challenge_row.scope == action,
         true <- challenge_row.binding["target_forum_host"] == operation["target_forum_host"],
         true <- challenge_row.binding["board_id"] == operation["board_id"],
         {:ok, credential_id} <- decode64(credential["rawId"] || credential["id"]),
         %WebauthnCredential{did: ^did} = stored <- Repo.get(WebauthnCredential, credential_id),
         :ok <- authorize_publication_credential(stored, action),
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
         :ok <- validate_sign_count(stored.sign_count, verified.sign_count),
         {:ok, _} <- update_sign_count(stored, verified.sign_count) do
      {:ok,
       %{
         "scheme" => "webauthn-p256-sha256",
         "delegation_id" => stored.delegation_id,
         "credential_public_key_thumbprint" => stored.credential_thumbprint,
         "challenge_id" => challenge_id,
         "operation_hash" => operation_hash,
         "client_data_json" => get_in(credential, ["response", "clientDataJSON"]),
         "authenticator_data" => get_in(credential, ["response", "authenticatorData"]),
         "signature" => get_in(credential, ["response", "signature"]),
         "verified_origin" => origin(),
         "verified_rp_id" => rp_id(),
         "user_present" => true,
         "user_verified" => true,
         "verified_at" => DateTime.utc_now() |> DateTime.to_iso8601()
       }}
    else
      false -> {:error, :operation_hash_mismatch}
      nil -> {:error, :credential_not_authorized}
      {:error, _} = error -> error
      _ -> {:error, :webauthn_verification_failed}
    end
  end

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

  def credential_summaries(did) when is_binary(did) do
    did
    |> list_credentials()
    |> Enum.map(fn credential ->
      %{
        "credential_id" => b64(credential.credential_id),
        "delegation_id" => credential.delegation_id,
        "rp_id" => credential.rp_id,
        "allowed_actions" => credential.allowed_actions,
        "delegation_expires_at" =>
          credential.delegation_expires_at &&
            DateTime.to_iso8601(credential.delegation_expires_at),
        "revoked_at" => credential.revoked_at && DateTime.to_iso8601(credential.revoked_at),
        "last_used_at" =>
          credential.last_used_at && DateTime.to_iso8601(credential.last_used_at)
      }
    end)
  end

  def revoke_credential(did, encoded_id, revocation, signature)
      when is_binary(did) and is_binary(encoded_id) and is_map(revocation) and
             is_binary(signature) do
    with {:ok, credential_id} <- decode64(encoded_id),
         %WebauthnCredential{did: ^did} = credential <-
           Repo.get(WebauthnCredential, credential_id),
         true <- revocation["type"] == "io.trisaura.identity.webCredentialRevocation",
         true <- revocation["version"] == 1,
         true <- revocation["subject_did"] == did,
         true <- revocation["credential_id"] == encoded_id,
         true <- is_binary(revocation["nonce"]) and revocation["nonce"] != "",
         {:ok, revoked_at, _} <- DateTime.from_iso8601(revocation["revoked_at"] || ""),
         true <- abs(DateTime.diff(DateTime.utc_now(), revoked_at, :second)) <= 300,
         true <- IdentityCache.verify_signature(did, canonical_json(revocation), signature),
         {:ok, updated} <-
           credential
           |> Ecto.Changeset.change(revoked_at: revoked_at)
           |> Repo.update() do
      {:ok, updated}
    else
      nil -> {:error, :unknown_credential}
      false -> {:error, :invalid_did_proof}
      {:error, _} = error -> error
      _ -> {:error, :invalid_did_proof}
    end
  end

  def revoke_credential(_did, _encoded_id, _revocation, _signature),
    do: {:error, :invalid_did_proof}

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

  defp persist_challenge(did, kind, challenge, opts \\ []) do
    attrs = %{
      challenge_id: token("wac"),
      did: did,
      kind: kind,
      scope: Keyword.get(opts, :scope, @scope),
      wax_challenge: :erlang.term_to_binary(challenge),
      session_id: Keyword.get(opts, :session_id),
      operation_id: Keyword.get(opts, :operation_id),
      operation_hash: Keyword.get(opts, :operation_hash),
      binding: Keyword.get(opts, :binding),
      expires_at: DateTime.add(DateTime.utc_now(), @challenge_ttl, :second)
    }

    %WebauthnChallenge{} |> WebauthnChallenge.changeset(attrs) |> Repo.insert!()
  end

  defp take_publication_challenge(id, did, session_id) do
    Repo.transaction(fn ->
      row =
        Repo.one(
          from(c in WebauthnChallenge,
            where: c.challenge_id == ^id,
            lock: "FOR UPDATE"
          )
        )

      case row do
        %WebauthnChallenge{
          did: ^did,
          kind: "web_publication",
          session_id: ^session_id,
          consumed_at: nil
        } = challenge_row ->
          if DateTime.compare(challenge_row.expires_at, DateTime.utc_now()) == :gt do
            challenge_row
            |> Ecto.Changeset.change(consumed_at: DateTime.utc_now())
            |> Repo.update!()

            {challenge_row, decode_term(challenge_row.wax_challenge)}
          else
            Repo.rollback(:expired_challenge)
          end

        %WebauthnChallenge{consumed_at: consumed_at} when not is_nil(consumed_at) ->
          Repo.rollback(:consumed_challenge)

        _ ->
          Repo.rollback(:invalid_challenge)
      end
    end)
    |> case do
      {:ok, {row, challenge}} -> {:ok, row, challenge}
      {:error, reason} -> {:error, reason}
    end
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

  defp save_credential(
         did,
         attested,
         response,
         delegation_signature,
         delegation_attrs
       ) do
    credential_thumbprint =
      :crypto.hash(:sha256, attested.credential_id)
      |> Base.url_encode64(padding: false)

    attrs = %{
      credential_id: attested.credential_id,
      did: did,
      cose_key: :erlang.term_to_binary(attested.credential_public_key),
      transports: get_in(response, ["response", "transports"]) || [],
      sign_count: 0,
      delegation_id: delegation_attrs[:delegation_id],
      credential_thumbprint: credential_thumbprint,
      rp_id: delegation_attrs[:rp_id],
      allowed_actions: delegation_attrs[:allowed_actions],
      delegation_signature: delegation_signature,
      delegation_expires_at: delegation_attrs[:delegation_expires_at]
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

  defp credential_descriptors(did) when is_binary(did),
    do: did |> list_credentials() |> credential_descriptors()

  defp credential_descriptors(credentials) when is_list(credentials) do
    Enum.map(credentials, fn credential ->
      %{
        "type" => "public-key",
        "id" => b64(credential.credential_id),
        "transports" => credential.transports
      }
    end)
  end

  defp active_publication_credentials(did, action) do
    now = DateTime.utc_now()

    Repo.all(
      from(c in WebauthnCredential,
        where:
          c.did == ^did and is_nil(c.revoked_at) and
            (is_nil(c.delegation_expires_at) or c.delegation_expires_at > ^now)
      )
    )
    |> Enum.filter(&(action in &1.allowed_actions))
  end

  defp authorize_publication_credential(stored, action) do
    cond do
      not is_nil(stored.revoked_at) -> {:error, :credential_revoked}
      is_nil(stored.delegation_id) -> {:error, :credential_not_authorized}
      stored.rp_id != rp_id() -> {:error, :credential_not_authorized}
      action not in stored.allowed_actions -> {:error, :credential_not_authorized}
      delegation_expired?(stored.delegation_expires_at) -> {:error, :credential_revoked}
      true -> :ok
    end
  end

  defp delegation_expired?(nil), do: false

  defp delegation_expired?(expires_at),
    do: DateTime.compare(expires_at, DateTime.utc_now()) != :gt

  defp verify_enrollment_did_proof(did, challenge_id, credential_id, signature, nil) do
    message = challenge_id <> "." <> b64(credential_id)

    if IdentityCache.verify_signature(did, message, signature),
      do: {:ok, %{delegation_id: nil, rp_id: nil, allowed_actions: []}},
      else: {:error, :invalid_did_proof}
  end

  defp verify_enrollment_did_proof(
         did,
         challenge_id,
         credential_id,
         signature,
         delegation
       )
       when is_map(delegation) do
    credential_id_hash =
      :crypto.hash(:sha256, credential_id)
      |> Base.encode16(case: :lower)

    allowed_actions = delegation["allowed_actions"]

    with {:ok, issued_at, _} <- DateTime.from_iso8601(delegation["issued_at"] || ""),
         {:ok, expires_at, _} <- DateTime.from_iso8601(delegation["expires_at"] || "") do
      valid? =
        delegation["type"] == "io.trisaura.identity.webCredentialDelegation" and
        delegation["version"] == 1 and
        delegation["challenge_id"] == challenge_id and
        delegation["subject_did"] == did and
        delegation["credential_id_hash"] == credential_id_hash and
        delegation["rp_id"] == rp_id() and
        is_binary(delegation["delegation_id"]) and
        is_list(allowed_actions) and allowed_actions != [] and
        MapSet.subset?(MapSet.new(allowed_actions), MapSet.new(@publication_actions)) and
        DateTime.compare(expires_at, issued_at) == :gt and
        DateTime.compare(expires_at, DateTime.utc_now()) == :gt and
        DateTime.diff(expires_at, issued_at, :second) <= 365 * 24 * 60 * 60 and
        IdentityCache.verify_signature(did, canonical_json(delegation), signature)

      if valid? do
        {:ok,
         %{
           delegation_id: delegation["delegation_id"],
           rp_id: delegation["rp_id"],
           allowed_actions: allowed_actions,
           delegation_expires_at: expires_at
         }}
      else
        {:error, :invalid_did_proof}
      end
    else
      _ -> {:error, :invalid_did_proof}
    end
  end

  defp verify_enrollment_did_proof(_did, _challenge_id, _credential_id, _signature, _delegation),
    do: {:error, :invalid_did_proof}

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

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)

  defp rp_id, do: Application.get_env(:ansible_relay, :webauthn_rp_id, "elix.cool")
  defp origin, do: Application.get_env(:ansible_relay, :webauthn_origin, "https://elix.cool")
  defp audience, do: Application.get_env(:ansible_relay, :relay_origin, origin())
  defp token(prefix), do: prefix <> "_" <> (:crypto.strong_rand_bytes(24) |> b64())
  defp b64(binary), do: Base.url_encode64(binary, padding: false)
  defp decode64(value) when is_binary(value), do: Base.url_decode64(value, padding: false)
  defp decode64(_), do: :error
  defp decode_term(binary), do: :erlang.binary_to_term(binary, [:safe])
end
