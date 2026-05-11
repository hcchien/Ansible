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

  defp approved_session(scopes, expires_at \\ nil) do
    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
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
end
