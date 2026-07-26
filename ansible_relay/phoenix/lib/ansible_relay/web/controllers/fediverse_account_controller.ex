defmodule AnsibleRelay.Web.Controllers.FediverseAccountController do
  import Plug.Conn

  alias AnsibleRelay.{ActivityPub.AccountDeletion, DidAccountCache, IdentityCache}

  @reason_codes ~w(user_requested identity_rotated)

  def delete(conn, params) do
    did = params["did"]
    reason = params["reason_code"] || "user_requested"
    requested_at = params["requested_at"]
    signature = params["signature"]

    with true <- is_binary(did) and is_binary(requested_at) and is_binary(signature),
         true <- reason in @reason_codes,
         {:ok, requested, _offset} <- DateTime.from_iso8601(requested_at),
         true <- abs(DateTime.diff(DateTime.utc_now(), requested, :second)) <= 300,
         :ok <- authorize_sync(conn, did),
         true <- IdentityCache.verified?(did),
         true <-
           IdentityCache.verify_signature(
             did,
             signing_payload(did, reason, requested_at),
             signature
           ),
         {:ok, %{handle: actor}} <- DidAccountCache.get(did),
         {:ok, result} <- AccountDeletion.request(did, actor, reason, base_url(conn)) do
      send_json(conn, 202, %{
        accepted: true,
        actor: actor,
        queued_delete_deliveries: result.deliveries,
        remote_erasure_guaranteed: false
      })
    else
      false ->
        send_json(conn, 401, %{error: "invalid_account_deletion_authorization"})

      {:error, :fediverse_account_not_found} ->
        send_json(conn, 404, %{error: "fediverse_account_not_found"})

      {:error, :invalid_sync_capability} ->
        send_json(conn, 401, %{error: "invalid_sync_capability"})

      {:error, _} ->
        send_json(conn, 422, %{error: "invalid_account_deletion_request"})

      _ ->
        send_json(conn, 503, %{error: "fediverse_account_deletion_unavailable"})
    end
  end

  def signing_payload(did, reason, requested_at) do
    Jason.encode!([did, "delete_fediverse_account", reason, requested_at])
  end

  defp authorize_sync(conn, did) do
    if AnsibleRelay.WebauthnSync.enforcement_enabled?(),
      do: AnsibleRelay.WebauthnSync.authorize(conn, did),
      else: :ok
  end

  defp base_url(conn) do
    Application.get_env(:ansible_relay, :relay_origin) ||
      "#{conn.scheme}://#{conn.host}"
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
