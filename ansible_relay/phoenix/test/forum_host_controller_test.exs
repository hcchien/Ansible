defmodule AnsibleRelay.Web.ForumHostControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{AbuseDetector, Repo, WebSessionStore}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case AbuseDetector.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> AbuseDetector.reset()
    end

    :ok
  end

  defp get_json(path) do
    conn(:get, path)
    |> Router.call(@router_opts)
  end

  defp post_json(path, body, headers) do
    Enum.reduce(headers, conn(:post, path, Jason.encode!(body)), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp approved_session_token(scopes, did \\ nil) do
    case WebSessionStore.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    did = did || "did:plc:forum#{System.unique_integer([:positive])}"
    device_id = "app_device_forum_#{System.unique_integer([:positive])}"

    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => scopes,
        "ttl_seconds" => 300
      })

    {:ok, session} =
      WebSessionStore.approve_challenge(challenge.challenge_id, %{
        subject_did: did,
        approving_device_id: device_id,
        scopes: scopes,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    session.session_token
  end

  test "GET /api/v1/forum-host exposes compliance, policy, host identity, and issuers" do
    response = get_json("/api/v1/forum-host")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["forum_host_id"] == "host-local-dev"
    assert body["server_kind"] == "ansibleForumHost"
    assert body["constitution_compliance"] in ["unknown", "compatible", "constitution_compliant"]
    assert is_map(body["rules"])
    assert is_map(body["posting_policy"])
    assert is_map(body["moderation_policy"])
    assert is_list(body["host_public_keys"])
    assert is_list(body["accepted_session_issuers"])
    assert body["capabilities"]["create_boards"] == true
    assert body["capabilities"]["announcements"] == true
  end

  test "GET /api/v1/forum-host/boards returns hosted boards" do
    response = get_json("/api/v1/forum-host/boards")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert is_list(body["boards"])

    board = Enum.find(body["boards"], &(&1["hosted_board_id"] == "general"))
    assert board["hosted_board_id"] == "general"
    assert board["canonical_board_uri"] == "http://localhost:4001/boards/general"
  end

  test "GET /api/v1/forum-host/announcements returns host-owned announcements" do
    original_announcements = Application.get_env(:ansible_relay, :forum_host_announcements)

    Application.put_env(:ansible_relay, :forum_host_announcements, [
      %{
        "announcement_id" => "host-rules",
        "owner_kind" => "forum_host",
        "title" => "Rules updated",
        "body" => "Posting policy was refreshed.",
        "severity" => "info",
        "locale" => "en"
      },
      %{
        "announcement_id" => "relay-maintenance",
        "owner_kind" => "relay",
        "title" => "Relay maintenance",
        "body" => "Relay work is scheduled.",
        "severity" => "info",
        "locale" => "en"
      }
    ])

    on_exit(fn ->
      if original_announcements do
        Application.put_env(:ansible_relay, :forum_host_announcements, original_announcements)
      else
        Application.delete_env(:ansible_relay, :forum_host_announcements)
      end
    end)

    response = get_json("/api/v1/forum-host/announcements")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)

    assert [%{"announcement_id" => "host-rules", "owner_kind" => "forum_host"}] =
             body["announcements"]
  end

  test "POST /api/v1/forum-host/boards accepts signed create-board intent" do
    did = "did:plc:board23456789"
    token = approved_session_token(["forum:post"], did)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        %{
          "intent_id" => "intent-1",
          "author_did" => did,
          "signature" => "sig-hex",
          "board" => %{
            "title" => "Reading Group",
            "description" => "Open discussion"
          }
        },
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 201

    body = Jason.decode!(response.resp_body)
    assert body["hosted_board_id"] == "reading-group"
    assert body["slug"] == "reading-group"
    assert body["title"] == "Reading Group"
  end

  test "web session must include forum:post to create a hosted web thread" do
    token = approved_session_token(["forum:read"])

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello"},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 403
  end

  test "web session with forum:post can create a hosted web thread" do
    did = "did:plc:forum23456789"
    token = approved_session_token(["forum:read", "forum:post"], did)

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello"},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 202
    body = Jason.decode!(response.resp_body)
    assert body["accepted"] == true
    assert body["subject_did"] == did
    assert body["trust_tier"] == "self_custody_did"
  end

  test "web thread creation is rate limited across sessions for the same DID" do
    case AbuseDetector.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> AbuseDetector.reset()
    end

    original_policy = Application.get_env(:ansible_relay, :abuse_detector)

    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 1, refill_per_second: 0, suspension_ms: 60_000}
    })

    on_exit(fn ->
      if original_policy do
        Application.put_env(:ansible_relay, :abuse_detector, original_policy)
      else
        Application.delete_env(:ansible_relay, :abuse_detector)
      end
    end)

    token = approved_session_token(["forum:read", "forum:post"])

    first =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello"},
        [{"authorization", "Bearer #{token}"}]
      )

    second =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Again"},
        [{"authorization", "Bearer #{token}"}]
      )

    assert first.status == 202
    assert second.status == 429
    assert Jason.decode!(second.resp_body)["error"] == "rate_limited"
  end
end
