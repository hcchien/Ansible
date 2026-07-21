defmodule AnsibleRelay.Web.Controllers.WebauthnSyncController do
  @moduledoc "WebAuthn enrollment and short-lived sync capability exchange."

  import Plug.Conn
  alias AnsibleRelay.WebauthnSync

  def registration_options(conn, params) do
    with {:ok, did} <- require_string(params, "did"),
         {:ok, options} <- WebauthnSync.registration_options(did) do
      send_json(conn, 200, options)
    else
      error -> send_error(conn, error)
    end
  end

  def finish_registration(conn, params) do
    with {:ok, did} <- require_string(params, "did"),
         {:ok, challenge_id} <- require_string(params, "challenge_id"),
         {:ok, credential} <- require_map(params, "credential"),
         {:ok, did_signature} <- require_string(params, "did_signature"),
         {:ok, saved} <-
           WebauthnSync.finish_registration(did, challenge_id, credential, did_signature) do
      send_json(conn, 201, %{
        enrolled: true,
        credential_id: Base.url_encode64(saved.credential_id, padding: false)
      })
    else
      error -> send_error(conn, error)
    end
  end

  def authentication_options(conn, params) do
    with {:ok, did} <- require_string(params, "did"),
         scope = params["scope"] || "sync:write",
         {:ok, options} <- WebauthnSync.authentication_options(did, scope) do
      send_json(conn, 200, options)
    else
      error -> send_error(conn, error)
    end
  end

  def exchange(conn, params) do
    with {:ok, did} <- require_string(params, "did"),
         {:ok, challenge_id} <- require_string(params, "challenge_id"),
         {:ok, credential} <- require_map(params, "credential"),
         scope = params["scope"] || "sync:write",
         {:ok, capability} <-
           WebauthnSync.finish_authentication(did, challenge_id, credential, scope) do
      send_json(conn, 200, capability)
    else
      error -> send_error(conn, error)
    end
  end

  defp require_string(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_field, key}}
    end
  end

  defp require_map(params, key) do
    case params[key] do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:missing_field, key}}
    end
  end

  defp send_error(conn, {:error, {:missing_field, field}}),
    do: send_json(conn, 422, %{error: "missing_field", field: field})

  defp send_error(conn, {:error, :unverified_did}),
    do: send_json(conn, 401, %{error: "unverified_did"})

  defp send_error(conn, {:error, :not_enrolled}),
    do: send_json(conn, 409, %{error: "passkey_not_enrolled"})

  defp send_error(conn, {:error, reason})
       when reason in [:invalid_scope, :invalid_challenge, :expired_challenge],
       do: send_json(conn, 401, %{error: to_string(reason)})

  defp send_error(conn, _),
    do: send_json(conn, 401, %{error: "webauthn_verification_failed"})

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
