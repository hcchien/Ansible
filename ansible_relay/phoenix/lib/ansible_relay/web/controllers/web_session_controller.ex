defmodule AnsibleRelay.Web.Controllers.WebSessionController do
  @moduledoc "App-mediated web session challenge, approval, and session endpoints."

  import Plug.Conn

  alias AnsibleRelay.{AbuseDetector, IdentityCache, SigVerifier, WebSessionStore}

  @allowed_scopes MapSet.new(["forum:read", "forum:post", "forum:reply", "identity:display"])
  @max_challenge_ttl_seconds 900
  @max_session_ttl_seconds 86_400
  @session_cookie_name "trisaura_session"

  def create_challenge(conn, params) do
    with {:ok, web_origin} <- validate_web_origin(params["web_origin"]),
         {:ok, relay_origin} <- validate_relay_origin(params["relay_origin"]),
         {:ok, audience} <- validate_audience(params["audience"] || relay_origin),
         {:ok, scopes} <- validate_scopes(params["scopes"]),
         :ok <- check_challenge_rate_limit(conn),
         ttl_seconds <- challenge_ttl(params["ttl_seconds"]),
         {:ok, challenge} <-
           WebSessionStore.issue_challenge(%{
             "web_origin" => web_origin,
             "relay_origin" => relay_origin,
             "audience" => audience,
             "scopes" => scopes,
             "ttl_seconds" => ttl_seconds
           }) do
      send_json(conn, 201, challenge_response(challenge))
    else
      {:error, :rate_limited, detail} ->
        send_json(conn, 429, %{error: "rate_limited", detail: detail})

      {:error, error} ->
        send_json(conn, 422, %{error: to_string(error)})
    end
  end

  def poll_challenge(conn, %{"challenge_id" => challenge_id}) do
    case WebSessionStore.poll_challenge(challenge_id) do
      {:ok, challenge} ->
        body = poll_challenge_response(challenge)

        if challenge.status == "approved" do
          with {:ok, session} <- WebSessionStore.get_session(challenge.approved_session_token) do
            body =
              Map.merge(body, %{
                trust_tier: session.trust_tier,
                subject_did: session.subject_did
              })

            conn
            |> set_session_cookie(session)
            |> send_json(200, body)
          else
            _ -> send_json(conn, 200, body)
          end
        else
          send_json(conn, 200, body)
        end

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "challenge_not_found"})
    end
  end

  def approve(conn, params) do
    with {:ok, challenge_id} <- require_string(params, "challenge_id"),
         {:ok, subject_did} <- require_string(params, "subject_did"),
         {:ok, grant} <- require_map(params, "grant"),
         {:ok, signature} <- require_string(params, "signature"),
         {:ok, challenge} <- WebSessionStore.get_challenge(challenge_id),
         :ok <- validate_grant(challenge, grant, subject_did),
         {:ok, grant_expires_at} <- parse_datetime(grant["expires_at"]),
         :ok <- validate_session_lifetime(grant_expires_at),
         {:ok, public_key} <- public_key_for(subject_did),
         true <- SigVerifier.verify_ed25519(public_key, canonical_json(grant), signature),
         {:ok, session} <-
           WebSessionStore.approve_challenge(challenge_id, %{
             subject_did: subject_did,
             approving_device_id: grant["approving_device_id"],
             scopes: grant["scopes"],
             expires_at: grant_expires_at
           }) do
      send_json(conn, 200, session_response(session, include_token: true))
    else
      {:error, :scope_not_allowed} ->
        send_json(conn, 422, %{error: "scope_not_allowed"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "challenge_not_found"})

      {:error, :unverified_did} ->
        send_json(conn, 401, %{error: "unverified_did"})

      {:error, :too_many_active_sessions} ->
        send_json(conn, 429, %{error: "too_many_active_sessions"})

      {:error, :approval_rate_limited} ->
        send_json(conn, 429, %{error: "approval_rate_limited"})

      false ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: to_string(error)})
    end
  end

  def reject(conn, params) do
    with {:ok, challenge_id} <- require_string(params, "challenge_id"),
         {:ok, challenge} <- WebSessionStore.reject_challenge(challenge_id) do
      send_json(conn, 200, %{challenge_id: challenge.challenge_id, status: challenge.status})
    else
      {:error, :not_found} -> send_json(conn, 404, %{error: "challenge_not_found"})
      {:error, error} -> send_json(conn, 422, %{error: to_string(error)})
    end
  end

  def revoke(conn, params) do
    with {:ok, token} <- session_token_from_conn(conn),
         {:ok, current_session} <- WebSessionStore.get_session(token),
         {:ok, target_token} <- revoke_target_token(current_session, params, token),
         {:ok, _session} <- WebSessionStore.revoke_session(target_token) do
      conn =
        if target_token == current_session.session_token do
          clear_session_cookie(conn)
        else
          conn
        end

      send_json(conn, 200, %{revoked: true})
    else
      {:error, :forbidden} -> send_json(conn, 403, %{error: "session_revoke_forbidden"})
      _ -> send_json(conn, 401, %{error: "invalid_web_session"})
    end
  end

  def me(conn, _headers) do
    with {:ok, token} <- session_token_from_conn(conn),
         {:ok, session} <- WebSessionStore.get_session(token) do
      send_json(conn, 200, session_response(session))
    else
      _ -> send_json(conn, 401, %{error: "invalid_web_session"})
    end
  end

  def list(conn, _params) do
    with {:ok, token} <- session_token_from_conn(conn),
         {:ok, session} <- WebSessionStore.get_session(token),
         {:ok, sessions} <- WebSessionStore.list_sessions_for_subject(session.subject_did) do
      send_json(conn, 200, %{sessions: Enum.map(sessions, &session_response/1)})
    else
      _ -> send_json(conn, 401, %{error: "invalid_web_session"})
    end
  end

  defp challenge_response(challenge) do
    deep_link =
      "trisaura://web-session/approve?" <>
        URI.encode_query(%{
          challenge_id: challenge.challenge_id,
          relay_origin: challenge.relay_origin
        })

    %{
      challenge_id: challenge.challenge_id,
      audience: challenge.audience,
      expires_at: DateTime.to_iso8601(challenge.expires_at),
      deep_link: deep_link,
      qr_payload: deep_link
    }
  end

  defp poll_challenge_response(challenge) do
    %{
      challenge_id: challenge.challenge_id,
      web_origin: challenge.web_origin,
      relay_origin: challenge.relay_origin,
      audience: challenge.audience,
      scopes: challenge.scopes,
      expires_at: DateTime.to_iso8601(challenge.expires_at),
      status: challenge.status
    }
  end

  defp session_response(session, opts \\ []) do
    response = %{
      session_id: session_id(session.session_token),
      subject_did: session.subject_did,
      approving_device_id: session.approving_device_id,
      web_origin: session.web_origin,
      relay_origin: session.relay_origin,
      audience: session.audience,
      trust_tier: session.trust_tier,
      scopes: session.scopes,
      created_at: DateTime.to_iso8601(session.created_at),
      expires_at: DateTime.to_iso8601(session.expires_at)
    }

    if Keyword.get(opts, :include_token, false) do
      Map.put(response, :session_token, session.session_token)
    else
      response
    end
  end

  defp validate_grant(challenge, grant, subject_did) do
    cond do
      grant["type"] != "io.trisaura.webSessionGrant" ->
        {:error, :invalid_grant_type}

      grant["version"] != 1 ->
        {:error, :invalid_grant_version}

      grant["challenge_id"] != challenge.challenge_id ->
        {:error, :challenge_mismatch}

      grant["relay_origin"] != challenge.relay_origin ->
        {:error, :relay_origin_mismatch}

      grant["web_origin"] != challenge.web_origin ->
        {:error, :web_origin_mismatch}

      grant["audience"] != challenge.audience ->
        {:error, :audience_mismatch}

      grant["subject_did"] != subject_did ->
        {:error, :subject_mismatch}

      not valid_string?(grant["approving_device_id"]) ->
        {:error, :missing_approving_device_id}

      not is_list(grant["scopes"]) ->
        {:error, :invalid_scopes}

      not MapSet.subset?(MapSet.new(grant["scopes"]), MapSet.new(challenge.scopes)) ->
        {:error, :scope_not_allowed}

      true ->
        :ok
    end
  end

  defp validate_web_origin(origin) do
    with {:ok, normalized_origin} <- validate_origin(origin, :web_origin),
         true <- normalized_origin in allowed_web_origins() do
      {:ok, normalized_origin}
    else
      {:error, error} -> {:error, error}
      false -> {:error, :web_origin_not_allowed}
    end
  end

  defp validate_origin(origin, error) when is_binary(origin) do
    uri = URI.parse(origin)

    if valid_origin_uri?(uri),
      do: {:ok, normalize_origin(uri)},
      else: {:error, error}
  end

  defp validate_origin(_origin, error), do: {:error, error}

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

  defp valid_string?(value), do: is_binary(value) && String.trim(value) != ""

  defp validate_relay_origin(origin) do
    configured = Application.get_env(:ansible_relay, :relay_origin, "http://localhost:4001")

    with {:ok, origin} <- validate_origin(origin, :relay_origin),
         true <- origin == normalize_origin_string(configured) do
      {:ok, origin}
    else
      {:error, error} -> {:error, error}
      false -> {:error, :relay_origin_mismatch}
    end
  end

  defp validate_audience(audience), do: validate_origin(audience, :invalid_audience)

  defp validate_scopes(scopes) when is_list(scopes) and scopes != [] do
    if MapSet.subset?(MapSet.new(scopes), @allowed_scopes),
      do: {:ok, scopes},
      else: {:error, :invalid_scopes}
  end

  defp validate_scopes(_scopes), do: {:error, :invalid_scopes}

  defp check_challenge_rate_limit(conn) do
    AbuseDetector.check_peer("web_session_challenge:" <> peer_hash(conn))
  end

  defp peer_hash(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp authorize_session_revoke(_current_session, target_token) when not is_binary(target_token),
    do: {:error, :forbidden}

  defp authorize_session_revoke(current_session, target_token) do
    if current_session.session_token == target_token do
      :ok
    else
      case WebSessionStore.get_session(target_token) do
        {:ok, %{subject_did: subject_did}} when subject_did == current_session.subject_did -> :ok
        _ -> {:error, :forbidden}
      end
    end
  end

  defp revoke_target_token(current_session, %{"session_id" => target_session_id}, _current_token)
       when is_binary(target_session_id) do
    with {:ok, sessions} <- WebSessionStore.list_sessions_for_subject(current_session.subject_did),
         %{session_token: token} <-
           Enum.find(sessions, &(session_id(&1.session_token) == target_session_id)) do
      {:ok, token}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp revoke_target_token(current_session, params, current_token) do
    target_token = Map.get(params, "session_token", current_token)

    with :ok <- authorize_session_revoke(current_session, target_token) do
      {:ok, target_token}
    end
  end

  defp allowed_web_origins do
    :ansible_relay
    |> Application.get_env(:web_allowed_origins, [
      "http://localhost:5173",
      "http://127.0.0.1:5173"
    ])
    |> Enum.map(&normalize_origin_string/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_origin_string(origin) when is_binary(origin) do
    case validate_origin(origin, :invalid_origin) do
      {:ok, normalized} -> normalized
      _ -> ""
    end
  end

  defp normalize_origin_string(_origin), do: ""

  defp normalize_origin(uri) do
    scheme = String.downcase(uri.scheme)
    host = canonical_loopback(authority_host(uri.host))
    port = if uri.port && uri.port != URI.default_port(scheme), do: ":#{uri.port}", else: ""
    "#{scheme}://#{host}#{port}"
  end

  # Loopback aliases all resolve to the local machine, so collapse them to one
  # identity for origin/audience comparison. Applied only here, not in
  # valid_authority?/1, so the strict Origin-header check keeps the literal host.
  # The IPv6 form is bracketed because authority_host/1 already wrapped it.
  @loopback_hosts ~w(localhost 127.0.0.1 [::1])

  defp canonical_loopback(host) do
    if host in @loopback_hosts, do: "localhost", else: host
  end

  defp session_id(session_token) do
    digest =
      :crypto.hash(:sha256, session_token)
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 22)

    "wsi_" <> digest
  end

  defp challenge_ttl(value) when is_integer(value), do: min(value, @max_challenge_ttl_seconds)

  defp challenge_ttl(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> min(parsed, @max_challenge_ttl_seconds)
      _ -> @max_challenge_ttl_seconds
    end
  end

  defp challenge_ttl(_value), do: 300

  defp validate_session_lifetime(expires_at) do
    now = DateTime.utc_now()
    max_expires_at = DateTime.add(now, @max_session_ttl_seconds, :second)

    cond do
      DateTime.compare(expires_at, now) != :gt -> {:error, :expired_grant}
      DateTime.compare(expires_at, max_expires_at) == :gt -> {:error, :session_too_long}
      true -> :ok
    end
  end

  defp public_key_for(did) do
    case IdentityCache.public_key_hex(did) do
      nil -> {:error, :unverified_did}
      public_key -> {:ok, public_key}
    end
  end

  defp require_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :"missing_#{key}"}
    end
  end

  defp require_map(params, key) do
    case Map.get(params, key) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, :"missing_#{key}"}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_expiry}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_expiry}

  defp set_session_cookie(conn, session) do
    max_age = max(DateTime.diff(session.expires_at, DateTime.utc_now(), :second), 0)
    secure = Application.get_env(:ansible_relay, :cookie_secure, true)

    put_resp_cookie(conn, @session_cookie_name, session.session_token,
      http_only: true,
      same_site: "Strict",
      secure: secure,
      max_age: max_age,
      path: "/"
    )
  end

  defp clear_session_cookie(conn) do
    secure = Application.get_env(:ansible_relay, :cookie_secure, true)

    put_resp_cookie(conn, @session_cookie_name, "",
      http_only: true,
      same_site: "Strict",
      secure: secure,
      max_age: 0,
      path: "/"
    )
  end

  defp session_token_from_conn(conn) do
    case bearer_token(conn) do
      {:ok, token} -> {:ok, token}
      {:error, :missing_token} -> cookie_token(conn)
      {:error, _error} = error -> error
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [] -> {:error, :missing_token}
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :invalid_token}
    end
  end

  defp cookie_token(conn) do
    conn = fetch_cookies(conn)

    case conn.cookies[@session_cookie_name] do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :missing_token}
    end
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

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
