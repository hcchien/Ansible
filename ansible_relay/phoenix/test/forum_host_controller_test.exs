defmodule AnsibleRelay.Web.ForumHostControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.ForumHost.SignedIntent
  alias AnsibleRelay.Db.ForumHostBoard
  alias AnsibleRelay.{AbuseDetector, DidAccountCache, IdentityCache, Repo, WebSessionStore}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    original_base_url = Application.get_env(:ansible_relay, :forum_host_base_url)
    Application.put_env(:ansible_relay, :forum_host_base_url, "http://localhost:4001")

    case AbuseDetector.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> AbuseDetector.reset()
    end

    on_exit(fn -> restore_env(:forum_host_base_url, original_base_url) end)

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

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp signed_create_board_intent(did, private_key, attrs \\ %{}) do
    payload =
      Map.merge(
        %{
          "type" => "io.trisaura.forum.createBoard",
          "version" => 1,
          "intent_id" => "intent-#{System.unique_integer([:positive])}",
          "author_did" => did,
          "target_forum_host" => "http://localhost:4001",
          "action" => "create_board",
          "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "expires_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 300, :second)),
          "board" => %{
            "title" => "Signed Reading",
            "description" => "Signed board"
          }
        },
        attrs
      )

    Map.put(payload, "signature", sign(private_key, SignedIntent.canonical_json(payload)))
  end

  defp cache_identity(did, public_key_hex, expires_at \\ nil) do
    IdentityCache.put(
      did,
      public_key_hex,
      "forum_host_controller_test_#{System.unique_integer([:positive])}",
      expires_at
    )
  end

  defp approved_session_token(scopes, did \\ nil, audience \\ "http://localhost:4001") do
    case WebSessionStore.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    did = did || "did:plc:forum#{System.unique_integer([:positive])}"
    device_id = "app_device_forum_#{System.unique_integer([:positive])}"

    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://elix.cool",
        "relay_origin" => "https://relay.elix.cool",
        "audience" => audience,
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

  test "POST /api/v1/forum-host/boards accepts app DID signed intent without web session" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:signedboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key),
        []
      )

    assert response.status == 201

    body = Jason.decode!(response.resp_body)
    assert body["hosted_board_id"] == "signed-reading"
    assert body["slug"] == "signed-reading"
    assert body["title"] == "Signed Reading"
  end

  test "POST /api/v1/forum-host/boards rejects tampered signed intent" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:tamperboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    body =
      did
      |> signed_create_board_intent(private_key)
      |> put_in(["board", "title"], "Tampered Title")

    response = post_json("/api/v1/forum-host/boards", body, [])

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "POST /api/v1/forum-host/boards rejects unsigned author DID" do
    response =
      post_json(
        "/api/v1/forum-host/boards",
        %{
          "type" => "io.trisaura.forum.createBoard",
          "version" => 1,
          "intent_id" => "intent-unsigned-#{System.unique_integer([:positive])}",
          "author_did" => "did:plc:unsigned#{System.unique_integer([:positive])}",
          "target_forum_host" => "http://localhost:4001",
          "action" => "create_board",
          "expires_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 300, :second)),
          "board" => %{"title" => "Unsigned"}
        },
        []
      )

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "POST /api/v1/forum-host/boards treats missing author DID as validation error" do
    response =
      post_json(
        "/api/v1/forum-host/boards",
        %{
          "type" => "io.trisaura.forum.createBoard",
          "version" => 1,
          "intent_id" => "intent-missing-author-#{System.unique_integer([:positive])}",
          "target_forum_host" => "http://localhost:4001",
          "action" => "create_board",
          "expires_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 300, :second)),
          "board" => %{"title" => "Missing Author"},
          "signature" => "00"
        },
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "missing_author_did"
  end

  test "POST /api/v1/forum-host/boards rejects unknown DID with valid signature" do
    {_public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:unknownboard#{System.unique_integer([:positive])}"

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key),
        []
      )

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "POST /api/v1/forum-host/boards rejects expired cached DID with valid signature" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:expiredboard#{System.unique_integer([:positive])}"

    :ok =
      cache_identity(
        did,
        public_key_hex,
        DateTime.add(DateTime.utc_now(), -60, :second)
      )

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key),
        []
      )

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "POST /api/v1/forum-host/boards rejects missing created_at" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:missingcreated#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    body =
      did
      |> signed_create_board_intent(private_key)
      |> Map.delete("created_at")

    response = post_json("/api/v1/forum-host/boards", body, [])

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "missing_created_at"
  end

  test "POST /api/v1/forum-host/boards rejects malformed created_at" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:badcreated#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "created_at" => "not-a-timestamp"
        }),
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_created_at"
  end

  test "POST /api/v1/forum-host/boards rejects future created_at by default" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:futurecreated#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    created_at = DateTime.add(DateTime.utc_now(), 60, :second)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "created_at" => DateTime.to_iso8601(created_at),
          "expires_at" => created_at |> DateTime.add(60, :second) |> DateTime.to_iso8601()
        }),
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "created_at_in_future"
  end

  test "POST /api/v1/forum-host/boards rejects overly long intent lifetime" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:longexpiry#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    created_at = DateTime.utc_now()

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "created_at" => DateTime.to_iso8601(created_at),
          "expires_at" => created_at |> DateTime.add(1_200, :second) |> DateTime.to_iso8601()
        }),
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "intent_lifetime_too_long"
  end

  test "POST /api/v1/forum-host/boards rejects mismatched audience" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:audienceboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "target_forum_host" => "https://other-forum.trisaura.test"
        }),
        []
      )

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "audience_mismatch"
  end

  test "POST /api/v1/forum-host/boards accepts a loopback-alias target host" do
    # Relay base_url is http://localhost:4001; an app pointed at the 127.0.0.1
    # alias must still pass the audience check (loopback resolves to one host).
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:loopbackboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "target_forum_host" => "http://127.0.0.1:4001",
          "board" => %{"title" => "Loopback Board #{System.unique_integer([:positive])}"}
        }),
        []
      )

    assert response.status == 201
  end

  test "GET /api/v1/forum-host/boards/created-by/:did lists only that DID's boards" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:creatorboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    created =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "board" => %{"title" => "Creator Owned #{System.unique_integer([:positive])}"}
        }),
        []
      )

    assert created.status == 201
    hosted_board_id = Jason.decode!(created.resp_body)["hosted_board_id"]

    response = get_json("/api/v1/forum-host/boards/created-by/#{did}")
    assert response.status == 200

    boards = Jason.decode!(response.resp_body)["boards"]
    ids = Enum.map(boards, & &1["hosted_board_id"])
    assert hosted_board_id in ids
    # Seed board "general" was not created by this DID, so it must not appear.
    refute "general" in ids
  end

  test "GET /api/v1/forum-host/boards/created-by/:did is empty for an unknown DID" do
    response = get_json("/api/v1/forum-host/boards/created-by/did:plc:nobody#{System.unique_integer([:positive])}")
    assert response.status == 200
    assert Jason.decode!(response.resp_body)["boards"] == []
  end

  test "POST /api/v1/forum-host/boards rejects changed duplicate intent" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:duplicateboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    intent_id = "intent-duplicate-#{System.unique_integer([:positive])}"

    first =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "intent_id" => intent_id,
          "board" => %{"title" => "Duplicate One"}
        }),
        []
      )

    second =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "intent_id" => intent_id,
          "board" => %{"title" => "Duplicate Two"}
        }),
        []
      )

    assert first.status == 201
    assert second.status == 409
    assert Jason.decode!(second.resp_body)["error"] == "duplicate_intent"
  end

  # ---- signed-intent board update (creator-only board management) ----

  defp signed_update_board_intent(did, private_key, board_id, attrs \\ %{}) do
    payload =
      Map.merge(
        %{
          "type" => "io.trisaura.forum.updateBoard",
          "version" => 1,
          "intent_id" => "intent-update-#{System.unique_integer([:positive])}",
          "author_did" => did,
          "board_id" => board_id,
          "target_forum_host" => "http://localhost:4001",
          "action" => "update_board",
          "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "expires_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 300, :second)),
          "board" => %{
            "title" => "Updated Title",
            "description" => "Updated description"
          }
        },
        attrs
      )

    Map.put(payload, "signature", sign(private_key, SignedIntent.canonical_json(payload)))
  end

  defp create_board_as(did, private_key, title) do
    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{"board" => %{"title" => title}}),
        []
      )

    assert response.status == 201
    Jason.decode!(response.resp_body)["hosted_board_id"]
  end

  test "POST boards/:id/update lets the creator update title, description, and policy" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updateowner#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Update Me #{System.unique_integer([:positive])}")

    response =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(did, private_key, board_id, %{
          "board" => %{
            "title" => "Renamed Board",
            "description" => "New description",
            "posting_policy" => %{"min_post_tier" => "verified_human"}
          }
        }),
        []
      )

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["hosted_board_id"] == board_id
    assert body["title"] == "Renamed Board"
    assert body["description"] == "New description"
    assert body["posting_policy"] == %{"min_post_tier" => "verified_human"}

    # The update is durable and the board identity is unchanged.
    listed = get_json("/api/v1/forum-host/boards/created-by/#{did}")
    board = listed.resp_body |> Jason.decode!() |> Map.fetch!("boards") |> hd()
    assert board["hosted_board_id"] == board_id
    assert board["title"] == "Renamed Board"
    assert board["slug"] == board_id
  end

  test "POST boards/:id/update leaves absent fields untouched" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:partialupdate#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    created =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "board" => %{
            "title" => "Partial #{System.unique_integer([:positive])}",
            "description" => "Keep me"
          }
        }),
        []
      )

    assert created.status == 201
    board_id = Jason.decode!(created.resp_body)["hosted_board_id"]

    response =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(did, private_key, board_id, %{
          "board" => %{"title" => "Partial Renamed"}
        }),
        []
      )

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["title"] == "Partial Renamed"
    assert body["description"] == "Keep me"
  end

  test "POST boards/:id/update rejects a non-creator DID with 403" do
    {owner_public_key, owner_private_key} = ed25519_keypair()
    owner_did = "did:plc:updateauthor#{System.unique_integer([:positive])}"
    :ok = cache_identity(owner_did, owner_public_key)
    board_id = create_board_as(owner_did, owner_private_key, "Owned #{System.unique_integer([:positive])}")

    {other_public_key, other_private_key} = ed25519_keypair()
    other_did = "did:plc:updatestranger#{System.unique_integer([:positive])}"
    :ok = cache_identity(other_did, other_public_key)

    response =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(other_did, other_private_key, board_id),
        []
      )

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "not_board_creator"
  end

  test "POST boards/:id/update rejects seed boards that have no creator record" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:seedupdater#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    # "general" is seeded from config, not created through an accepted intent.
    get_json("/api/v1/forum-host/boards")

    response =
      post_json(
        "/api/v1/forum-host/boards/general/update",
        signed_update_board_intent(did, private_key, "general"),
        []
      )

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "not_board_creator"
  end

  test "POST boards/:id/update rejects a tampered signed intent" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updatetamper#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Tamper #{System.unique_integer([:positive])}")

    body =
      did
      |> signed_update_board_intent(private_key, board_id)
      |> put_in(["board", "title"], "Tampered After Signing")

    response = post_json("/api/v1/forum-host/boards/#{board_id}/update", body, [])

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "POST boards/:id/update replays are idempotent; changed replays are rejected" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updatereplay#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Replay #{System.unique_integer([:positive])}")
    intent_id = "intent-update-replay-#{System.unique_integer([:positive])}"

    intent =
      signed_update_board_intent(did, private_key, board_id, %{
        "intent_id" => intent_id,
        "board" => %{"title" => "Replay Renamed"}
      })

    first = post_json("/api/v1/forum-host/boards/#{board_id}/update", intent, [])
    replay = post_json("/api/v1/forum-host/boards/#{board_id}/update", intent, [])

    changed =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(did, private_key, board_id, %{
          "intent_id" => intent_id,
          "board" => %{"title" => "Replay Renamed Differently"}
        }),
        []
      )

    assert first.status == 200
    assert replay.status == 200
    assert Jason.decode!(replay.resp_body)["title"] == "Replay Renamed"
    assert changed.status == 409
    assert Jason.decode!(changed.resp_body)["error"] == "duplicate_intent"
  end

  test "POST boards/:id/update rejects an unknown posting_policy min_post_tier" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updatebadtier#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Bad Tier #{System.unique_integer([:positive])}")

    response =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(did, private_key, board_id, %{
          "board" => %{"posting_policy" => %{"min_post_tier" => "vip"}}
        }),
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_min_post_tier"
  end

  test "POST boards/:id/update rejects external_inclusion with a trust gate" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updateconflict#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Conflict #{System.unique_integer([:positive])}")

    response =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(did, private_key, board_id, %{
          "board" => %{
            "posting_policy" => %{
              "external_inclusion" => true,
              "min_post_tier" => "verified_human"
            }
          }
        }),
        []
      )

    assert response.status == 422

    assert Jason.decode!(response.resp_body)["error"] ==
             "external_inclusion_conflicts_with_trust_gate"
  end

  test "POST boards/:id/update 404s for a missing board" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updatemissing#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards/no-such-board/update",
        signed_update_board_intent(did, private_key, "no-such-board"),
        []
      )

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "board_not_found"
  end

  test "POST boards/:id/update rejects a path/payload board_id mismatch" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updatemismatch#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Mismatch #{System.unique_integer([:positive])}")

    response =
      post_json(
        "/api/v1/forum-host/boards/some-other-board/update",
        signed_update_board_intent(did, private_key, board_id),
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "board_id_mismatch"
  end

  test "POST boards/:id/update rejects a mismatched audience" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updateaudience#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Audience #{System.unique_integer([:positive])}")

    response =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(did, private_key, board_id, %{
          "target_forum_host" => "https://other-forum.trisaura.test"
        }),
        []
      )

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "audience_mismatch"
  end

  test "POST boards/:id/update rejects an empty update payload" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:updateempty#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)
    board_id = create_board_as(did, private_key, "Empty #{System.unique_integer([:positive])}")

    response =
      post_json(
        "/api/v1/forum-host/boards/#{board_id}/update",
        signed_update_board_intent(did, private_key, board_id, %{"board" => %{}}),
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_board"
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

  test "web thread creation rejects web session for a different audience" do
    token =
      approved_session_token(
        ["forum:read", "forum:post"],
        "did:plc:forumaudience23456789",
        "https://other-forum.trisaura.test"
      )

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello"},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "audience_mismatch"
  end

  test "web thread creation accepts a web session with a loopback-alias audience" do
    # Relay audience is http://localhost:4001; a session bound to the 127.0.0.1
    # alias must still pass the audience check.
    did = "did:plc:loopbackaudience23456789"

    token =
      approved_session_token(
        ["forum:read", "forum:post"],
        did,
        "http://127.0.0.1:4001"
      )

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello"},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
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

  # ---- posting_policy["min_post_tier"] gate ----

  defp insert_hosted_board(posting_policy) do
    board_id = "gated-board-#{System.unique_integer([:positive])}"

    Repo.insert!(%ForumHostBoard{
      hosted_board_id: board_id,
      slug: board_id,
      canonical_board_uri: "http://localhost:4001/boards/#{board_id}",
      title: "Gated Board #{board_id}",
      posting_policy: posting_policy
    })

    board_id
  end

  defp seed_reputation_tier(did, tier) do
    case DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok =
      DidAccountCache.put(
        did,
        "pubkey_hex_forum_tier_test",
        "forum_tier_handle_#{System.unique_integer([:positive])}",
        reputation_tier: tier
      )
  end

  test "GET /api/v1/forum-host/boards exposes posting_policy min_post_tier" do
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})

    response = get_json("/api/v1/forum-host/boards")
    assert response.status == 200

    board =
      response.resp_body
      |> Jason.decode!()
      |> Map.fetch!("boards")
      |> Enum.find(&(&1["hosted_board_id"] == board_id))

    assert board["posting_policy"] == %{"min_post_tier" => "verified_human"}
  end

  test "GET /api/v1/discover/boards exposes posting_policy min_post_tier" do
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})

    response = get_json("/api/v1/discover/boards?q=#{board_id}")
    assert response.status == 200

    assert [board] = Jason.decode!(response.resp_body)["boards"]
    assert board["hosted_board_id"] == board_id
    assert board["posting_policy"]["min_post_tier"] == "verified_human"
  end

  test "GET /api/v1/forum-host exposes the configured posting_policy min_post_tier" do
    original_policy = Application.get_env(:ansible_relay, :forum_host_posting_policy)

    Application.put_env(:ansible_relay, :forum_host_posting_policy, %{
      "min_trust_tier" => "self_custody_did",
      "min_post_tier" => "verified_human"
    })

    on_exit(fn -> restore_env(:forum_host_posting_policy, original_policy) end)

    response = get_json("/api/v1/forum-host")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["posting_policy"]["min_post_tier"] == "verified_human"
  end

  test "POST /api/v1/forum-host/boards rejects an unknown posting_policy min_post_tier" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:badtierboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "board" => %{
            "title" => "Bad Tier",
            "posting_policy" => %{"min_post_tier" => "vip"}
          }
        }),
        []
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_min_post_tier"
  end

  test "POST /api/v1/forum-host/boards stores and returns posting_policy min_post_tier" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:gatedboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "board" => %{
            "title" => "Humans Only #{System.unique_integer([:positive])}",
            "posting_policy" => %{"min_post_tier" => "verified_human"}
          }
        }),
        []
      )

    assert response.status == 201

    body = Jason.decode!(response.resp_body)
    assert body["posting_policy"] == %{"min_post_tier" => "verified_human"}
  end

  test "GET /api/v1/forum-host/boards exposes posting_policy external_inclusion" do
    board_id = insert_hosted_board(%{"external_inclusion" => true})

    response = get_json("/api/v1/forum-host/boards")
    assert response.status == 200

    board =
      response.resp_body
      |> Jason.decode!()
      |> Map.fetch!("boards")
      |> Enum.find(&(&1["hosted_board_id"] == board_id))

    assert board["posting_policy"]["external_inclusion"] == true
  end

  test "GET /api/v1/discover/boards exposes posting_policy external_inclusion" do
    board_id = insert_hosted_board(%{"external_inclusion" => true})

    response = get_json("/api/v1/discover/boards?q=#{board_id}")
    assert response.status == 200

    assert [board] = Jason.decode!(response.resp_body)["boards"]
    assert board["hosted_board_id"] == board_id
    assert board["posting_policy"]["external_inclusion"] == true
  end

  test "GET /api/v1/forum-host exposes the configured posting_policy external_inclusion" do
    original_policy = Application.get_env(:ansible_relay, :forum_host_posting_policy)

    Application.put_env(:ansible_relay, :forum_host_posting_policy, %{
      "min_trust_tier" => "self_custody_did",
      "external_inclusion" => true
    })

    on_exit(fn -> restore_env(:forum_host_posting_policy, original_policy) end)

    response = get_json("/api/v1/forum-host")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["posting_policy"]["external_inclusion"] == true
  end

  test "POST /api/v1/forum-host/boards stores and returns posting_policy external_inclusion" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:externalboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "board" => %{
            "title" => "External Mix #{System.unique_integer([:positive])}",
            "posting_policy" => %{"external_inclusion" => true}
          }
        }),
        []
      )

    assert response.status == 201
    assert Jason.decode!(response.resp_body)["posting_policy"]["external_inclusion"] == true
  end

  test "POST /api/v1/forum-host/boards rejects external_inclusion with a trust gate (422 reason code)" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:conflictboard#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/boards",
        signed_create_board_intent(did, private_key, %{
          "board" => %{
            "title" => "Conflict #{System.unique_integer([:positive])}",
            "posting_policy" => %{
              "external_inclusion" => true,
              "min_post_tier" => "verified_human"
            }
          }
        }),
        []
      )

    assert response.status == 422

    assert Jason.decode!(response.resp_body)["error"] ==
             "external_inclusion_conflicts_with_trust_gate"
  end

  test "web thread creation in a gated board rejects a basic session DID with the 403 contract" do
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})
    did = "did:plc:gatedbasic#{System.unique_integer([:positive])}"
    token = approved_session_token(["forum:read", "forum:post"], did)

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello", "board_id" => board_id},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 403

    assert Jason.decode!(response.resp_body) == %{
             "error" => "posting_requires_tier",
             "required_tier" => "verified_human",
             "current_tier" => "basic"
           }
  end

  test "web thread creation in a gated board accepts a verified_human session DID" do
    board_id = insert_hosted_board(%{"min_post_tier" => "verified_human"})
    did = "did:plc:gatedhuman#{System.unique_integer([:positive])}"
    seed_reputation_tier(did, "verified_human")
    token = approved_session_token(["forum:read", "forum:post"], did)

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello", "board_id" => board_id},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
  end

  test "web thread creation in an ungated board stays open to a basic session DID" do
    board_id = insert_hosted_board(%{"min_trust_tier" => "self_custody_did"})
    did = "did:plc:ungatedbasic#{System.unique_integer([:positive])}"
    token = approved_session_token(["forum:read", "forum:post"], did)

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello", "board_id" => board_id},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 202
  end

  test "web thread creation rejects an unknown board_id" do
    token = approved_session_token(["forum:read", "forum:post"])

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Hello", "board_id" => "no-such-board"},
        [{"authorization", "Bearer #{token}"}]
      )

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "board_not_found"
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
