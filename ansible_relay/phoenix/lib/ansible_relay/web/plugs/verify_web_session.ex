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
      [] ->
        cookie_token(conn)

      ["Bearer " <> token] when token != "" ->
        {:ok, token}

      _ ->
        {:error, :invalid_token}
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
    with {:ok, session_audience} <- normalize_origin(audience),
         {:ok, required_audience} <- normalize_origin(required_audience),
         true <- session_audience == required_audience do
      :ok
    else
      _ -> {:error, :audience_mismatch}
    end
  end

  defp require_audience(_session, _required_audience), do: {:error, :audience_mismatch}

  defp normalize_origin(value) when is_binary(value) do
    uri = URI.parse(value)

    if valid_origin_uri?(uri) do
      scheme = String.downcase(uri.scheme)
      host = authority_host(uri.host)
      port = if uri.port && uri.port != URI.default_port(scheme), do: ":#{uri.port}", else: ""
      {:ok, "#{scheme}://#{host}#{port}"}
    else
      {:error, :invalid_origin}
    end
  end

  defp normalize_origin(_value), do: {:error, :invalid_origin}

  defp valid_origin_uri?(uri) do
    uri.scheme in ["http", "https"] && is_binary(uri.host) && uri.host != "" &&
      is_nil(uri.userinfo) && uri.path in [nil, ""] && is_nil(uri.query) &&
      is_nil(uri.fragment) && valid_authority?(uri)
  end

  defp valid_authority?(%URI{authority: authority, scheme: scheme, host: host, port: port})
       when is_binary(authority) and is_integer(port) do
    authority = String.downcase(authority)

    scheme
    |> valid_authorities(host, port)
    |> Enum.any?(&(String.downcase(&1) == authority))
  end

  defp valid_authority?(_uri), do: false

  defp valid_authorities(scheme, host, port) do
    host = authority_host(host)
    default_port = URI.default_port(scheme)

    if port == default_port do
      [host, "#{host}:#{port}"]
    else
      ["#{host}:#{port}"]
    end
  end

  defp authority_host(host) do
    host = String.downcase(host)

    if String.contains?(host, ":") do
      "[#{host}]"
    else
      host
    end
  end

  defp send_error(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end
end
