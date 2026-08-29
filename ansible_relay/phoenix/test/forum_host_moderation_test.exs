defmodule AnsibleRelay.Web.ForumHostModerationTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.ForumHost.{ReportRateLimiter, SignedIntent}
  alias AnsibleRelay.Db.{ForumHostBoard, ForumHostModerationAction, ForumHostReport}
  alias AnsibleRelay.{AbuseDetector, IdentityCache, OpStore, Repo, WebSessionStore}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    original_base_url = Application.get_env(:ansible_relay, :forum_host_base_url)
    Application.put_env(:ansible_relay, :forum_host_base_url, "http://localhost:4001")

    for mod <- [
          IdentityCache,
          AbuseDetector,
          OpStore,
          AnsibleRelay.DidAccountCache,
          WebSessionStore,
          ReportRateLimiter
        ] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    AbuseDetector.reset()
    ReportRateLimiter.reset()

    on_exit(fn -> restore_env(:forum_host_base_url, original_base_url) end)

    :ok
  end

  # ---- Helpers ----

  defp get_json(path, headers \\ []) do
    Enum.reduce(headers, conn(:get, path), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
    |> Router.call(@router_opts)
  end

  defp post_json(path, body, headers \\ []) do
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

  defp cache_identity(did, public_key_hex) do
    IdentityCache.put(
      did,
      public_key_hex,
      "forum_moderation_test_#{System.unique_integer([:positive])}"
    )
  end

  defp approved_session_token(scopes, did \\ nil, audience \\ "http://localhost:4001") do
    did = did || "did:plc:modweb#{System.unique_integer([:positive])}"
    device_id = "app_device_mod_#{System.unique_integer([:positive])}"

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

  defp insert_hosted_board do
    board_id = "mod-board-#{System.unique_integer([:positive])}"

    Repo.insert!(%ForumHostBoard{
      hosted_board_id: board_id,
      slug: board_id,
      canonical_board_uri: "http://localhost:4001/boards/#{board_id}",
      title: "Moderated Board #{board_id}"
    })

    board_id
  end

  defp set_host_owner(did) do
    original = Application.get_env(:ansible_relay, :forum_host_owner_did)
    Application.put_env(:ansible_relay, :forum_host_owner_did, did)
    on_exit(fn -> restore_env(:forum_host_owner_did, original) end)
    did
  end

  defp auth(token), do: [{"authorization", "Bearer #{token}"}]

  defp web_report(token, board_id, overrides \\ %{}) do
    body =
      Map.merge(
        %{
          "target_kind" => "post",
          "target_ref" => "post-#{System.unique_integer([:positive])}",
          "board_id" => board_id,
          "reason_code" => "spam"
        },
        overrides
      )

    post_json("/api/v1/forum-host/web/reports", body, auth(token))
  end

  defp signed_report_intent(did, private_key, report, attrs \\ %{}) do
    payload =
      Map.merge(
        %{
          "type" => "io.trisaura.forum.reportContent",
          "version" => 1,
          "intent_id" => "intent-report-#{System.unique_integer([:positive])}",
          "author_did" => did,
          "target_forum_host" => "http://localhost:4001",
          "action" => "report_content",
          "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "expires_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 300, :second)),
          "report" => report
        },
        attrs
      )

    Map.put(payload, "signature", sign(private_key, SignedIntent.canonical_json(payload)))
  end

  defp moderation_action(token, board_id, action, target_ref, overrides \\ %{}) do
    body =
      Map.merge(
        %{
          "action" => action,
          "target_ref" => target_ref,
          "board_id" => board_id,
          "reason_code" => "spam"
        },
        overrides
      )

    post_json("/api/v1/forum-host/web/moderation/actions", body, auth(token))
  end

  # Owner session + board, ready for moderation calls.
  defp moderator_context do
    board_id = insert_hosted_board()
    owner_did = set_host_owner("did:plc:hostowner#{System.unique_integer([:positive])}")
    owner_token = approved_session_token(["forum:read", "forum:post"], owner_did)
    {board_id, owner_did, owner_token}
  end

  defp append_op(entity_type, entity_id, payload \\ "cGF5bG9hZA==") do
    {:ok, _log_id} =
      OpStore.append(%{
        op_id: "op-mod-#{System.unique_integer([:positive])}",
        author_did: "did:plc:author#{System.unique_integer([:positive])}",
        entity_type: entity_type,
        entity_id: entity_id,
        op_type: "insert",
        payload: payload,
        signature: "00"
      })

    :ok
  end

  defp signed_post_op(did, private_key, thread_id) do
    op = %{
      "op_id" => "op-signed-#{System.unique_integer([:positive])}",
      "author_did" => did,
      "entity_type" => "post",
      "entity_id" => "entity-#{System.unique_integer([:positive])}",
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(%{"threadId" => thread_id, "body" => "hello"}))
    }

    Map.put(op, "signature", sign(private_key, op_signing_payload(op)))
  end

  defp op_signing_payload(op) do
    op
    |> Map.take(~w(author_did entity_id entity_type op_id op_type payload))
    |> SignedIntent.canonical_json()
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)

  # ---- Reports: web-session rail ----

  test "POST /api/v1/forum-host/web/reports files a report from a web session" do
    board_id = insert_hosted_board()
    did = "did:plc:reporter#{System.unique_integer([:positive])}"
    token = approved_session_token(["forum:read", "forum:post"], did)

    response = web_report(token, board_id, %{"target_ref" => "post-abc"})

    assert response.status == 201
    report = Jason.decode!(response.resp_body)["report"]
    assert report["target_kind"] == "post"
    assert report["target_ref"] == "post-abc"
    assert report["board_id"] == board_id
    assert report["reporter_did"] == did
    assert report["reason_code"] == "spam"
    assert report["status"] == "open"
  end

  test "POST /api/v1/forum-host/web/reports rejects an unknown reason code" do
    board_id = insert_hosted_board()
    token = approved_session_token(["forum:read", "forum:post"])

    response = web_report(token, board_id, %{"reason_code" => "i_disagree"})

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_reason_code"
  end

  test "POST /api/v1/forum-host/web/reports requires a note for reason other" do
    board_id = insert_hosted_board()
    token = approved_session_token(["forum:read", "forum:post"])

    missing = web_report(token, board_id, %{"reason_code" => "other"})
    assert missing.status == 422
    assert Jason.decode!(missing.resp_body)["error"] == "invalid_reason_code"

    with_note = web_report(token, board_id, %{"reason_code" => "other", "note" => "weird spam"})
    assert with_note.status == 201
    assert Jason.decode!(with_note.resp_body)["report"]["note"] == "weird spam"
  end

  test "POST /api/v1/forum-host/web/reports rejects an unknown board" do
    token = approved_session_token(["forum:read", "forum:post"])

    response = web_report(token, "no-such-board")

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "unknown_target"
  end

  test "POST /api/v1/forum-host/web/reports rejects an unknown target kind" do
    board_id = insert_hosted_board()
    token = approved_session_token(["forum:read", "forum:post"])

    response = web_report(token, board_id, %{"target_kind" => "user"})

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "unknown_target"
  end

  test "duplicate open report from the same reporter collapses to the existing report" do
    board_id = insert_hosted_board()
    did = "did:plc:dupereporter#{System.unique_integer([:positive])}"
    token = approved_session_token(["forum:read", "forum:post"], did)

    first = web_report(token, board_id, %{"target_ref" => "post-dupe"})
    second = web_report(token, board_id, %{"target_ref" => "post-dupe"})

    assert first.status == 201
    assert second.status == 200

    first_id = Jason.decode!(first.resp_body)["report"]["id"]
    assert Jason.decode!(second.resp_body)["report"]["id"] == first_id
    assert Repo.aggregate(ForumHostReport, :count) == 1
  end

  test "report submissions are rate limited per reporter DID with the 429 contract" do
    board_id = insert_hosted_board()
    did = "did:plc:spamreporter#{System.unique_integer([:positive])}"
    token = approved_session_token(["forum:read", "forum:post"], did)

    original_limits = Application.get_env(:ansible_relay, :forum_host_report_limits)

    Application.put_env(:ansible_relay, :forum_host_report_limits, %{
      "basic" => %{capacity: 1, refill_per_second: 0, suspension_ms: 60_000}
    })

    on_exit(fn -> restore_env(:forum_host_report_limits, original_limits) end)

    first = web_report(token, board_id, %{"target_ref" => "post-one"})
    second = web_report(token, board_id, %{"target_ref" => "post-two"})

    assert first.status == 201
    assert second.status == 429
    assert Jason.decode!(second.resp_body) == %{"error" => "rate_limited"}
  end

  # ---- Reports: signed-intent rail (app) ----

  test "POST /api/v1/forum-host/reports accepts a signed report_content intent" do
    board_id = insert_hosted_board()
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:appreporter#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/reports",
        signed_report_intent(did, private_key, %{
          "target_kind" => "thread",
          "target_ref" => "thread-77",
          "board_id" => board_id,
          "reason_code" => "harassment"
        })
      )

    assert response.status == 201
    report = Jason.decode!(response.resp_body)["report"]
    assert report["reporter_did"] == did
    assert report["target_kind"] == "thread"
    assert report["reason_code"] == "harassment"
    assert report["status"] == "open"
  end

  test "POST /api/v1/forum-host/reports rejects a tampered signed report intent" do
    board_id = insert_hosted_board()
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:tamperreport#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    body =
      did
      |> signed_report_intent(private_key, %{
        "target_kind" => "post",
        "target_ref" => "post-1",
        "board_id" => board_id,
        "reason_code" => "spam"
      })
      |> put_in(["report", "target_ref"], "post-2")

    response = post_json("/api/v1/forum-host/reports", body)

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "POST /api/v1/forum-host/reports rejects an unknown reason code on the app rail" do
    board_id = insert_hosted_board()
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:appbadreason#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response =
      post_json(
        "/api/v1/forum-host/reports",
        signed_report_intent(did, private_key, %{
          "target_kind" => "post",
          "target_ref" => "post-1",
          "board_id" => board_id,
          "reason_code" => "i_disagree"
        })
      )

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_reason_code"
  end

  # ---- Moderation console authorization ----

  test "GET /api/v1/forum-host/web/moderation/reports lists open reports for the host owner" do
    {board_id, _owner_did, owner_token} = moderator_context()
    reporter_token = approved_session_token(["forum:read", "forum:post"])

    assert web_report(reporter_token, board_id, %{"target_ref" => "post-queue"}).status == 201

    response =
      get_json("/api/v1/forum-host/web/moderation/reports?status=open", auth(owner_token))

    assert response.status == 200
    reports = Jason.decode!(response.resp_body)["reports"]
    assert [%{"target_ref" => "post-queue", "status" => "open"}] = reports
  end

  test "GET /api/v1/forum-host/web/moderation/reports rejects a non-owner session" do
    {board_id, _owner_did, _owner_token} = moderator_context()
    reporter_token = approved_session_token(["forum:read", "forum:post"])
    assert web_report(reporter_token, board_id).status == 201

    outsider_token = approved_session_token(["forum:read", "forum:post"])
    response = get_json("/api/v1/forum-host/web/moderation/reports", auth(outsider_token))

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "not_board_moderator"
  end

  test "POST /api/v1/forum-host/web/moderation/actions rejects a non-moderator session" do
    {board_id, _owner_did, _owner_token} = moderator_context()
    outsider_token = approved_session_token(["forum:read", "forum:post"])

    response = moderation_action(outsider_token, board_id, "remove_post_from_board", "post-x")

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "not_board_moderator"
  end

  test "GET /api/v1/forum-host/web/moderation/actions rejects a non-moderator session" do
    set_host_owner("did:plc:hostowner#{System.unique_integer([:positive])}")
    outsider_token = approved_session_token(["forum:read", "forum:post"])

    response = get_json("/api/v1/forum-host/web/moderation/actions", auth(outsider_token))

    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "not_board_moderator"
  end

  # ---- Moderation actions: audit trail + report transitions ----

  test "remove_post_from_board writes an audit row and transitions the report to actioned" do
    {board_id, owner_did, owner_token} = moderator_context()
    reporter_token = approved_session_token(["forum:read", "forum:post"])

    report_response = web_report(reporter_token, board_id, %{"target_ref" => "post-bad"})
    report_id = Jason.decode!(report_response.resp_body)["report"]["id"]

    response =
      moderation_action(owner_token, board_id, "remove_post_from_board", "post-bad", %{
        "report_id" => report_id
      })

    assert response.status == 201
    action = Jason.decode!(response.resp_body)["action"]
    assert action["action"] == "remove_post_from_board"
    assert action["moderator_did"] == owner_did
    assert action["reason_code"] == "spam"
    assert action["report_id"] == report_id

    # Audit row persisted (time-stamped, attributed, reason-coded).
    audit = Repo.get!(ForumHostModerationAction, action["id"])
    assert audit.moderator_did == owner_did
    assert audit.reason_code == "spam"
    assert audit.inserted_at

    # The audit list endpoint serves the same row to the moderator.
    list = get_json("/api/v1/forum-host/web/moderation/actions", auth(owner_token))
    assert list.status == 200
    assert [%{"action" => "remove_post_from_board"}] = Jason.decode!(list.resp_body)["actions"]

    # Report transitioned open -> actioned, so the open queue is now empty.
    assert Repo.get!(ForumHostReport, report_id).status == "actioned"
    queue = get_json("/api/v1/forum-host/web/moderation/reports?status=open", auth(owner_token))
    assert Jason.decode!(queue.resp_body)["reports"] == []
  end

  test "dismiss_report transitions the report to dismissed without projection effects" do
    {board_id, _owner_did, owner_token} = moderator_context()
    reporter_token = approved_session_token(["forum:read", "forum:post"])

    report_response = web_report(reporter_token, board_id, %{"target_ref" => "post-fine"})
    report_id = Jason.decode!(report_response.resp_body)["report"]["id"]

    response =
      moderation_action(owner_token, board_id, "dismiss_report", "post-fine", %{
        "report_id" => report_id
      })

    assert response.status == 201
    assert Repo.get!(ForumHostReport, report_id).status == "dismissed"

    # No tombstone: dismissal leaves the board projection untouched.
    state = get_json("/api/v1/forum-host/boards/#{board_id}/moderation-state")
    assert Jason.decode!(state.resp_body)["removed_posts"] == []
  end

  test "POST /api/v1/forum-host/web/moderation/actions rejects an unknown action or reason" do
    {board_id, _owner_did, owner_token} = moderator_context()

    bad_action = moderation_action(owner_token, board_id, "ban_user", "post-x")
    assert bad_action.status == 422
    assert Jason.decode!(bad_action.resp_body)["error"] == "invalid_action"

    bad_reason =
      moderation_action(owner_token, board_id, "lock_thread", "thread-x", %{
        "reason_code" => "because"
      })

    assert bad_reason.status == 422
    assert Jason.decode!(bad_reason.resp_body)["error"] == "invalid_reason_code"
  end

  # ---- Projection effects: public moderation state + listings ----

  test "GET /api/v1/forum-host/boards/:board_id/moderation-state is public and reason-coded" do
    {board_id, _owner_did, owner_token} = moderator_context()

    assert moderation_action(owner_token, board_id, "remove_post_from_board", "post-gone", %{
             "reason_code" => "illegal_content"
           }).status == 201

    assert moderation_action(owner_token, board_id, "lock_thread", "thread-frozen", %{
             "reason_code" => "off_topic"
           }).status == 201

    # No authorization header: the moderation state is a public surface.
    response = get_json("/api/v1/forum-host/boards/#{board_id}/moderation-state")

    assert response.status == 200

    assert Jason.decode!(response.resp_body) == %{
             "removed_posts" => [
               %{"target_ref" => "post-gone", "reason_code" => "illegal_content"}
             ],
             "locked_threads" => [
               %{"thread_id" => "thread-frozen", "reason_code" => "off_topic"}
             ],
             "hidden_context_notes" => []
           }
  end

  test "context-note reports and host-scoped hiding are public and reason-coded" do
    {board_id, _owner_did, owner_token} = moderator_context()
    reporter = approved_session_token(["forum:read", "forum:post"])

    report =
      web_report(reporter, board_id, %{
        "target_kind" => "context_note",
        "target_ref" => "context-note-harmful"
      })

    assert report.status == 201
    assert Jason.decode!(report.resp_body)["report"]["target_kind"] == "context_note"

    action =
      moderation_action(
        owner_token,
        board_id,
        "hide_context_note",
        "context-note-harmful",
        %{"reason_code" => "harassment"}
      )

    assert action.status == 201

    state = get_json("/api/v1/forum-host/boards/#{board_id}/moderation-state")

    assert Jason.decode!(state.resp_body)["hidden_context_notes"] == [
             %{"note_id" => "context-note-harmful", "reason_code" => "harassment"}
           ]
  end

  test "GET /api/v1/forum-host/boards/:board_id/moderation-state rejects an unknown board" do
    response = get_json("/api/v1/forum-host/boards/no-such-board/moderation-state")

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "board_not_found"
  end

  test "removed posts become content-stripped tombstones in op listings" do
    {board_id, _owner_did, owner_token} = moderator_context()
    :ok = append_op("post", "post-tombstone")
    :ok = append_op("post", "post-untouched")

    assert moderation_action(owner_token, board_id, "remove_post_from_board", "post-tombstone").status ==
             201

    response = get_json("/api/v1/ops/delta?cursor=0")
    assert response.status == 200
    ops = Jason.decode!(response.resp_body)["ops"]

    tombstone = Enum.find(ops, &(&1["entity_id"] == "post-tombstone"))
    assert tombstone["removed"] == true
    assert tombstone["reason_code"] == "spam"
    assert tombstone["payload"] == nil
    assert tombstone["signature"] == nil

    untouched = Enum.find(ops, &(&1["entity_id"] == "post-untouched"))
    refute Map.has_key?(untouched, "removed")
    assert untouched["payload"] == "cGF5bG9hZA=="
  end

  test "locked threads carry the lock state in op listings" do
    {board_id, _owner_did, owner_token} = moderator_context()
    :ok = append_op("thread", "thread-locked")

    assert moderation_action(owner_token, board_id, "lock_thread", "thread-locked", %{
             "reason_code" => "harassment"
           }).status == 201

    response = get_json("/api/v1/ops/delta?cursor=0")
    ops = Jason.decode!(response.resp_body)["ops"]

    locked = Enum.find(ops, &(&1["entity_id"] == "thread-locked"))
    assert locked["locked"] == true
    assert locked["lock_reason_code"] == "harassment"
    # A lock never strips content — only removal does.
    assert locked["payload"] == "cGF5bG9hZA=="
  end

  # ---- Lock enforcement at both write chokepoints ----

  test "locked thread rejects new posts at the signed-ops chokepoint" do
    {board_id, _owner_did, owner_token} = moderator_context()
    thread_id = "thread-ops-locked-#{System.unique_integer([:positive])}"

    assert moderation_action(owner_token, board_id, "lock_thread", thread_id, %{
             "reason_code" => "off_topic"
           }).status == 201

    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:lockedposter#{System.unique_integer([:positive])}"
    :ok = cache_identity(did, public_key_hex)

    response = post_json("/api/v1/ops", signed_post_op(did, private_key, thread_id))

    assert response.status == 403

    assert Jason.decode!(response.resp_body) == %{
             "error" => "thread_locked",
             "reason_code" => "off_topic"
           }
  end

  test "locked thread legacy web route requires passkey author proof" do
    {board_id, _owner_did, owner_token} = moderator_context()
    thread_id = "thread-web-locked-#{System.unique_integer([:positive])}"

    assert moderation_action(owner_token, board_id, "lock_thread", thread_id).status == 201

    token = approved_session_token(["forum:read", "forum:post"])

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Reply", "board_id" => board_id, "thread_id" => thread_id},
        auth(token)
      )

    assert response.status == 409
    assert Jason.decode!(response.resp_body)["error"] == "passkey_author_proof_required"
  end

  test "unlock_thread clears public lock state but legacy web route remains disabled" do
    {board_id, _owner_did, owner_token} = moderator_context()
    thread_id = "thread-unlock-#{System.unique_integer([:positive])}"

    assert moderation_action(owner_token, board_id, "lock_thread", thread_id).status == 201
    assert moderation_action(owner_token, board_id, "unlock_thread", thread_id).status == 201

    token = approved_session_token(["forum:read", "forum:post"])

    response =
      post_json(
        "/api/v1/forum-host/web/threads",
        %{"title" => "Reply", "board_id" => board_id, "thread_id" => thread_id},
        auth(token)
      )

    assert response.status == 409

    state = get_json("/api/v1/forum-host/boards/#{board_id}/moderation-state")
    assert Jason.decode!(state.resp_body)["locked_threads"] == []
  end
end
