defmodule AnsibleRelay.Web.VerifyWebSessionTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Plugs.VerifyWebSession
  alias AnsibleRelay.WebSessionStore

  setup do
    case WebSessionStore.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> WebSessionStore.reset()
    end

    :ok
  end

  defp approved_session(scopes, expires_at \\ nil, attrs \\ %{}) do
    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "audience" => Map.get(attrs, :audience),
        "scopes" => scopes,
        "ttl_seconds" => 300
      })

    {:ok, session} =
      WebSessionStore.approve_challenge(challenge.challenge_id, %{
        subject_did: "did:plc:plug23456789",
        approving_device_id: "app_device_plug",
        scopes: scopes,
        expires_at: expires_at || DateTime.add(DateTime.utc_now(), 300, :second)
      })

    session
  end

  test "missing bearer token returns 401" do
    conn = VerifyWebSession.call(conn(:post, "/"), ["forum:post"])

    assert conn.status == 401
    assert conn.halted
  end

  test "unknown token returns 401" do
    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer missing")
      |> VerifyWebSession.call(["forum:post"])

    assert conn.status == 401
    assert conn.halted
  end

  test "bearer token takes precedence over cookie token" do
    cookie_session = approved_session(["forum:post"])
    bearer_session = approved_session(["forum:read"])

    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer #{bearer_session.session_token}")
      |> put_req_cookie("trisaura_session", cookie_session.session_token)
      |> VerifyWebSession.call(["forum:post"])

    assert conn.status == 403
    assert conn.halted
    assert Jason.decode!(conn.resp_body)["error"] == "missing_required_scope"
  end

  test "malformed authorization header does not fall back to cookie token" do
    cookie_session = approved_session(["forum:post"])

    for authorization <- ["Basic #{cookie_session.session_token}", "Bearer "] do
      conn =
        conn(:post, "/")
        |> put_req_header("authorization", authorization)
        |> put_req_cookie("trisaura_session", cookie_session.session_token)
        |> VerifyWebSession.call(["forum:post"])

      assert conn.status == 401
      assert conn.halted
      assert Jason.decode!(conn.resp_body)["error"] == "invalid_web_session"
    end
  end

  test "expired token returns 401" do
    session = approved_session(["forum:post"], DateTime.add(DateTime.utc_now(), -1, :second))

    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer #{session.session_token}")
      |> VerifyWebSession.call(["forum:post"])

    assert conn.status == 401
    assert conn.halted
  end

  test "missing required scope returns 403" do
    session = approved_session(["forum:read"])

    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer #{session.session_token}")
      |> VerifyWebSession.call(["forum:post"])

    assert conn.status == 403
    assert conn.halted
  end

  test "missing required scope returns 403 before audience checks" do
    session = approved_session(["forum:read"], nil, %{audience: "http://localhost:4001"})

    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer #{session.session_token}")
      |> VerifyWebSession.call(["forum:post"], audience: "https://other-host.test")

    assert conn.status == 403
    assert conn.halted
    assert Jason.decode!(conn.resp_body)["error"] == "missing_required_scope"
  end

  test "valid token assigns web session and verified DID" do
    session = approved_session(["forum:read", "forum:post"])

    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer #{session.session_token}")
      |> VerifyWebSession.call(["forum:post"])

    refute conn.halted
    assert conn.assigns.verified_did == "did:plc:plug23456789"
    assert conn.assigns.web_session.session_token == session.session_token
  end

  test "valid cookie token assigns web session" do
    session = approved_session(["forum:post"])

    conn =
      conn(:post, "/")
      |> put_req_cookie("trisaura_session", session.session_token)
      |> VerifyWebSession.call(["forum:post"])

    refute conn.halted
    assert conn.assigns.web_session.session_token == session.session_token
  end

  test "valid token with matching normalized audience assigns web session" do
    session = approved_session(["forum:post"], nil, %{audience: "http://localhost:4001"})

    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer #{session.session_token}")
      |> VerifyWebSession.call(["forum:post"], audience: "http://LOCALHOST:4001")

    refute conn.halted
    assert conn.assigns.web_session.session_token == session.session_token
  end

  test "required audience with path query or fragment returns 403" do
    session = approved_session(["forum:post"], nil, %{audience: "http://localhost:4001"})

    for audience <- [
          "http://localhost:4001/path",
          "http://localhost:4001?debug=true",
          "http://localhost:4001#fragment"
        ] do
      conn =
        conn(:post, "/")
        |> put_req_header("authorization", "Bearer #{session.session_token}")
        |> VerifyWebSession.call(["forum:post"], audience: audience)

      assert conn.status == 403
      assert conn.halted
      assert Jason.decode!(conn.resp_body)["error"] == "audience_mismatch"
    end
  end

  test "stored audience with path query or fragment returns 403" do
    for audience <- [
          "http://localhost:4001/path",
          "http://localhost:4001?debug=true",
          "http://localhost:4001#fragment"
        ] do
      session = approved_session(["forum:post"], nil, %{audience: audience})

      conn =
        conn(:post, "/")
        |> put_req_header("authorization", "Bearer #{session.session_token}")
        |> VerifyWebSession.call(["forum:post"], audience: "http://localhost:4001")

      assert conn.status == 403
      assert conn.halted
      assert Jason.decode!(conn.resp_body)["error"] == "audience_mismatch"
    end
  end

  test "wrong required audience returns 403" do
    session = approved_session(["forum:post"], nil, %{audience: "http://localhost:4001"})

    conn =
      conn(:post, "/")
      |> put_req_header("authorization", "Bearer #{session.session_token}")
      |> VerifyWebSession.call(["forum:post"], audience: "https://other-host.test")

    assert conn.status == 403
    assert conn.halted
    assert Jason.decode!(conn.resp_body)["error"] == "audience_mismatch"
  end
end
