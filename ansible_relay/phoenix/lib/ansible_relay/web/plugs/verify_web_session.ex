defmodule AnsibleRelay.Web.Plugs.VerifyWebSession do
  @moduledoc "Verifies relay-issued web session bearer tokens and required scopes."

  import Plug.Conn

  alias AnsibleRelay.WebSessionStore

  def call(conn, required_scopes) when is_list(required_scopes) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, session} <- WebSessionStore.get_session(token),
         :ok <- require_scopes(session.scopes, required_scopes) do
      conn
      |> assign(:web_session, session)
      |> assign(:verified_did, session.subject_did)
    else
      {:error, :missing_scope} ->
        send_error(conn, 403, "missing_required_scope")

      _ ->
        send_error(conn, 401, "invalid_web_session")
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp require_scopes(session_scopes, required_scopes) do
    if MapSet.subset?(MapSet.new(required_scopes), MapSet.new(session_scopes)),
      do: :ok,
      else: {:error, :missing_scope}
  end

  defp send_error(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end
end
