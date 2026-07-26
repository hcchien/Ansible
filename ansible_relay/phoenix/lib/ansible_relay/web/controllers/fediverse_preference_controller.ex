defmodule AnsibleRelay.Web.Controllers.FediversePreferenceController do
  @moduledoc "Accepts versioned, DID-signed ActivityPub consent and host policy."

  import Plug.Conn

  alias AnsibleRelay.{
    DidAccountCache,
    FediversePreferences,
    IdentityCache,
    IdentityWritePolicy,
    ReputationTier
  }

  @required ~w(did enabled default_note_visibility allow_remote_followers domain_policy revision signature)
  @signature_schemes ~w(ed25519 p256-sha256)

  def update(conn, params) do
    with :ok <- required(params),
         :ok <- validate_values(params),
         :ok <- IdentityWritePolicy.validate(params["signature_scheme"]),
         :ok <- authorize_sync(conn, params["did"]),
         :ok <- verify_identity(params),
         {:ok, actor, tier} <- account(params["did"]),
         :ok <- authorize_enable(params["enabled"], tier),
         attrs <- normalize(params, actor),
         {:ok, preference} <- FediversePreferences.put(attrs) do
      send_json(conn, 200, public(preference))
    else
      {:error, :missing_fields, fields} ->
        send_json(conn, 422, %{error: "missing_required_fields", fields: fields})

      {:error, :invalid_preference} ->
        send_json(conn, 422, %{error: "invalid_fediverse_preference"})

      {:error, :unsupported_signing_algorithm} ->
        send_json(conn, 422, %{error: "unsupported_signing_algorithm"})

      {:error, :invalid_sync_capability} ->
        send_json(conn, 401, %{error: "invalid_sync_capability"})

      {:error, :unverified_did} ->
        send_json(conn, 401, %{error: "unverified_did"})

      {:error, :bad_signature} ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :account_unavailable} ->
        send_json(conn, 503, %{error: "fediverse_account_unavailable"})

      {:error, :requires_verified_human} ->
        send_json(conn, 403, %{error: "activity_pub_requires_verified_human"})

      {:error, :stale_revision} ->
        send_json(conn, 409, %{error: "stale_fediverse_preference_revision"})

      {:error, %Ecto.Changeset{}} ->
        send_json(conn, 422, %{error: "invalid_fediverse_preference"})
    end
  end

  def signing_payload(params) do
    Jason.encode!([
      params["did"],
      params["enabled"],
      params["default_note_visibility"],
      params["allow_remote_followers"],
      params["domain_policy"],
      FediversePreferences.normalize_domains(params["allowed_domains"] || []),
      FediversePreferences.normalize_domains(params["blocked_domains"] || []),
      FediversePreferences.normalize_actors(params["blocked_actors"] || []),
      params["revision"]
    ])
  end

  defp required(params) do
    missing = Enum.filter(@required, &(!Map.has_key?(params, &1) or is_nil(params[&1])))
    if missing == [], do: :ok, else: {:error, :missing_fields, missing}
  end

  defp validate_values(params) do
    valid =
      is_binary(params["did"]) and params["did"] != "" and
        is_binary(params["signature"]) and params["signature"] != "" and
        is_boolean(params["enabled"]) and
        is_boolean(params["allow_remote_followers"]) and
        params["default_note_visibility"] in ["public", "unlisted"] and
        params["domain_policy"] in ["open", "allowlist"] and
        params["signature_scheme"] in @signature_schemes and
        is_integer(params["revision"]) and params["revision"] > 0 and
        string_list?(params["allowed_domains"] || []) and
        string_list?(params["blocked_domains"] || []) and
        string_list?(params["blocked_actors"] || [])

    if valid, do: :ok, else: {:error, :invalid_preference}
  end

  defp string_list?(values) when is_list(values),
    do: length(values) <= 1_000 and Enum.all?(values, &is_binary/1)

  defp string_list?(_), do: false

  defp authorize_sync(conn, did) do
    if AnsibleRelay.WebauthnSync.enforcement_enabled?(),
      do: AnsibleRelay.WebauthnSync.authorize(conn, did),
      else: :ok
  end

  defp verify_identity(params) do
    did = params["did"]

    cond do
      !IdentityCache.verified?(did) -> {:error, :unverified_did}
      IdentityCache.verify_signature(did, signing_payload(params), params["signature"]) -> :ok
      true -> {:error, :bad_signature}
    end
  end

  defp account(did) do
    case DidAccountCache.get(did) do
      {:ok, %{handle: actor, reputation_tier: tier}}
      when is_binary(actor) and actor != "" -> {:ok, actor, tier}

      _ -> {:error, :account_unavailable}
    end
  end

  # Exit remains possible after credential expiry or a trust downgrade.
  defp authorize_enable(false, _tier), do: :ok

  defp authorize_enable(true, tier) do
    if ReputationTier.meets?(tier, "verified_human"),
      do: :ok,
      else: {:error, :requires_verified_human}
  end

  defp normalize(params, actor) do
    %{
      did: params["did"],
      actor: actor,
      enabled: params["enabled"],
      default_note_visibility: params["default_note_visibility"],
      allow_remote_followers: params["allow_remote_followers"],
      domain_policy: params["domain_policy"],
      allowed_domains: FediversePreferences.normalize_domains(params["allowed_domains"] || []),
      blocked_domains: FediversePreferences.normalize_domains(params["blocked_domains"] || []),
      blocked_actors: FediversePreferences.normalize_actors(params["blocked_actors"] || []),
      revision: params["revision"],
      signature: String.downcase(params["signature"]),
      signature_scheme: params["signature_scheme"]
    }
  end

  defp public(preference) do
    %{
      did: preference.did,
      actor: preference.actor,
      enabled: preference.enabled,
      default_note_visibility: preference.default_note_visibility,
      allow_remote_followers: preference.allow_remote_followers,
      domain_policy: preference.domain_policy,
      allowed_domains: preference.allowed_domains,
      blocked_domains: preference.blocked_domains,
      blocked_actors: preference.blocked_actors,
      revision: preference.revision
    }
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
