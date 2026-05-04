defmodule AnsibleRelay.Web.Controllers.IdentityController do
  @moduledoc "Phase 1 — Identity Anchoring endpoint."

  import Plug.Conn
  alias AnsibleRelay.{IdentityCache, SigVerifier, ZkpKeyRegistry}

  @challenge_required_fields ~w(did)
  @anchor_required_fields ~w(
    did
    zkp_proof
    zkp_circuit_version
    verification_key_hash
    nullifier
    public_key
    challenge
    challenge_signature
  )

  # POST /api/v1/identity/challenge
  def challenge(conn, params) do
    with :ok <- validate_fields(params, @challenge_required_fields),
         did = params["did"],
         {:ok, entry} <- IdentityCache.issue_challenge(did) do
      send_json(conn, 200, %{
        did: did,
        challenge: entry.challenge,
        expires_at: DateTime.to_iso8601(entry.expires_at)
      })
    else
      {:error, :missing_fields, fields} ->
        send_json(conn, 422, %{error: "missing_required_fields", fields: fields})
    end
  end

  # POST /api/v1/identity/anchor
  def anchor(conn, params) do
    with :ok <- validate_fields(params, @anchor_required_fields),
         did = params["did"],
         nullifier = params["nullifier"],
         public_key = params["public_key"],
         challenge = params["challenge"],
         :ok <- check_nullifier_unique(nullifier),
         :ok <- ZkpKeyRegistry.verify(params["zkp_circuit_version"], params["verification_key_hash"]),
         :ok <- verify_zkp_stub(params["zkp_proof"], params["zkp_circuit_version"]),
         :ok <- verify_challenge_signature(public_key, challenge, params["challenge_signature"]),
         :ok <- IdentityCache.consume_challenge(did, challenge) do
      IdentityCache.put(did, public_key, nullifier)

      expires_at =
        DateTime.utc_now()
        |> DateTime.add(
          Application.get_env(:ansible_relay, :did_cache_ttl_seconds, 7_776_000),
          :second
        )
        |> DateTime.to_iso8601()

      send_json(conn, 200, %{verified: true, did: did, expires_at: expires_at})
    else
      {:error, :missing_fields, fields} ->
        send_json(conn, 422, %{error: "missing_required_fields", fields: fields})

      {:error, :duplicate_nullifier} ->
        send_json(conn, 409, %{
          error: "duplicate_nullifier",
          message: "This passport has already been used to create an identity."
        })

      {:error, :invalid_zkp} ->
        send_json(conn, 401, %{error: "invalid_zkp_proof"})

      {:error, :unsupported_zkp_circuit} ->
        send_json(conn, 422, %{error: "unsupported_zkp_circuit"})

      {:error, :inactive_zkp_circuit} ->
        send_json(conn, 401, %{error: "inactive_zkp_circuit"})

      {:error, :verification_key_hash_mismatch} ->
        send_json(conn, 401, %{error: "verification_key_hash_mismatch"})

      {:error, :invalid_challenge_signature} ->
        send_json(conn, 401, %{error: "invalid_challenge_signature"})

      {:error, :invalid_challenge} ->
        send_json(conn, 401, %{error: "invalid_challenge"})

      {:error, :expired_challenge} ->
        send_json(conn, 401, %{error: "expired_challenge"})
    end
  end

  # --- Private helpers ---

  defp validate_fields(params, required) do
    missing = Enum.filter(required, &(is_nil(params[&1]) or params[&1] == ""))
    if missing == [], do: :ok, else: {:error, :missing_fields, missing}
  end

  defp check_nullifier_unique(nullifier) do
    if IdentityCache.nullifier_exists?(nullifier) do
      {:error, :duplicate_nullifier}
    else
      :ok
    end
  end

  defp verify_zkp_stub(_zkp_proof, _circuit_version) do
    # TODO(Q2): call SigVerifier or a dedicated ZKP verifier NIF
    :ok
  end

  defp verify_challenge_signature(public_key, challenge, signature) do
    if SigVerifier.verify_ed25519(public_key, challenge, signature),
      do: :ok,
      else: {:error, :invalid_challenge_signature}
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
