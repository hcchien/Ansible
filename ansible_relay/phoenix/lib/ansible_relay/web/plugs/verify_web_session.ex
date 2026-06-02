defmodule AnsibleRelay.Web.Plugs.VerifyWebSession do
  @moduledoc "Verifies relay-issued web session bearer tokens and required scopes."

  import Plug.Conn

  alias AnsibleRelay.WebSessionStore

  @session_cookie_name "trisaura_session"

  def call(conn, required_scopes, opts \\ []) when is_list(required_scopes) do
    with {:ok, token} <- session_token(conn),
         {:ok, session} <- WebSessionStore.get_session(token),
         :ok <- require_scopes(session.scopes, required_scopes),
         :ok <- require_audience(session, Keyword.get(opts, :audience)) do
      conn
      |> assign(:web_session, session)
      |> assign(:verified_did, session.subject_did)
    else
      {:error, :missing_scope} ->
        send_error(conn, 403, "missing_required_scope")

      {:error, :audience_mismatch} ->
        send_error(conn, 403, "audience_mismatch")

      _ ->
        send_error(conn, 401, "invalid_web_session")
    end
  end

  defp session_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> cookie_token(conn)
    end
  end

  defp cookie_token(conn) do
    conn = fetch_cookies(conn)

    case conn.req_cookies[@session_cookie_name] || conn.cookies[@session_cookie_name] do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp require_scopes(session_scopes, required_scopes) do
    if MapSet.subset?(MapSet.new(required_scopes), MapSet.new(session_scopes)),
      do: :ok,
      else: {:error, :missing_scope}
  end

  defp require_audience(_session, nil), do: :ok

  defp require_audience(%{audience: audience}, required_audience) do
    session_audience = normalize_origin(audience)
    required_audience = normalize_origin(required_audience)

    if session_audience != "" && session_audience == required_audience,
      do: :ok,
      else: {:error, :audience_mismatch}
  end

  defp require_audience(_session, _required_audience), do: {:error, :audience_mismatch}

  defp normalize_origin(value) when is_binary(value) do
    uri = URI.parse(value)

    if uri.scheme in ["http", "https"] && is_binary(uri.host) && uri.host != "" do
      scheme = String.downcase(uri.scheme)
      host = String.downcase(uri.host)
      port = if uri.port && uri.port != URI.default_port(scheme), do: ":#{uri.port}", else: ""
      "#{scheme}://#{host}#{port}"
    else
      ""
    end
  end

  defp normalize_origin(_value), do: ""

  defp send_error(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end
end
