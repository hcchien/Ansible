defmodule AnsibleRelay.Web.CommunityNotesRatingTest do
  use ExUnit.Case, async: false
  use Plug.Test

  import Ecto.Query

  alias AnsibleRelay.CommunityNotes.RateLimiter
  alias AnsibleRelay.Db.ForumHostContextNoteRating
  alias AnsibleRelay.ForumHost.SignedIntent
  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{AbuseDetector, DidAccountCache, IdentityCache, Metrics, OpStore, Repo}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    for mod <- [IdentityCache, AbuseDetector, OpStore, DidAccountCache, RateLimiter] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    original_host = Application.get_env(:ansible_relay, :forum_host_base_url)
    original_limits = Application.get_env(:ansible_relay, :community_notes_rating_limits)
    Application.put_env(:ansible_relay, :forum_host_base_url, "http://localhost:4001")
    Application.delete_env(:ansible_relay, :community_notes_rating_limits)
    AbuseDetector.reset()
    RateLimiter.reset()

    on_exit(fn ->
      restore_env(:forum_host_base_url, original_host)
      restore_env(:community_notes_rating_limits, original_limits)
    end)

    :ok
  end

  test "stores a signed private rating and exposes only an opaque rater key" do
    {_author, _author_key, _target, note} = create_note()
    {rater, rater_key} = identity("private-rater")

    response = rate(note["entity_id"], rater, rater_key, "helpful", ["good_sources"])

    assert response.status == 201
    body = Jason.decode!(response.resp_body)
    assert body["rating"]["level"] == "helpful"
    assert is_binary(body["rating"]["rater_key"])
    refute body["rating"]["rater_key"] == rater
    refute response.resp_body =~ rater

    stored =
      Repo.one!(from(r in ForumHostContextNoteRating, where: r.note_id == ^note["entity_id"]))

    assert stored.rater_did == rater
    assert stored.signed_intent["signature"]

    status = get_json("/api/v1/forum-host/community-notes/#{note["entity_id"]}/status")
    assert status.status == 200
    refute status.resp_body =~ rater
    refute Jason.decode!(status.resp_body)["status"] |> Map.has_key?("raters")
  end

  test "rejects tampering, invalid rating values, and author self-ratings" do
    {author, author_key, _target, note} = create_note()
    {rater, rater_key} = identity("validation-rater")

    tampered = rating_intent(note["entity_id"], rater, rater_key, "helpful", ["good_sources"])
    tampered = Map.put(tampered, "level", "not_helpful")
    response = post_json(rating_path(note), tampered)
    assert response.status == 401

    invalid = rating_intent(note["entity_id"], rater, rater_key, "helpful", ["made_up"])
    response = post_json(rating_path(note), invalid)
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_rating"

    response = rate(note["entity_id"], author, author_key, "helpful", ["good_sources"])
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "self_rating_forbidden"
  end

  test "replays are idempotent and a new intent replaces the same rater's prior rating" do
    {_author, _author_key, _target, note} = create_note()
    {rater, rater_key} = identity("replacement-rater")
    intent = rating_intent(note["entity_id"], rater, rater_key, "helpful", ["good_sources"])

    assert post_json(rating_path(note), intent).status == 201
    replay = post_json(rating_path(note), intent)
    assert replay.status == 200
    assert Jason.decode!(replay.resp_body)["duplicate"] == true

    replacement =
      rating_intent(note["entity_id"], rater, rater_key, "not_helpful", ["incorrect"])

    assert post_json(rating_path(note), replacement).status == 201

    rows = Repo.all(from(r in ForumHostContextNoteRating, where: r.note_id == ^note["entity_id"]))
    assert [%{level: "not_helpful", tags: ["incorrect"]}] = rows
  end

  test "requires quorum and reaches helpful consensus with two verified humans" do
    {_author, _author_key, target, note} = create_note()

    initial = status(note)
    assert initial["status"] == "needs_more_ratings"
    assert initial["rating_count"] == 0

    Enum.each(1..5, fn index ->
      tier = if index <= 2, do: "verified_human", else: "basic"
      {did, key} = identity("helpful-#{index}", tier)
      assert rate(note["entity_id"], did, key, "helpful", ["good_sources"]).status == 201
    end)

    result = status(note)
    assert result["status"] == "helpful"
    assert result["score"] == 1.0
    assert result["rating_count"] == 5
    assert result["verified_human_count"] == 2
    assert result["level_counts"]["helpful"] == 5
    assert result["scorer_id"] == "elix_host_consensus"
    assert result["scorer_version"] == 1
    assert String.starts_with?(result["input_hash"], "sha256:")

    listing =
      get_json("/api/v1/forum-host/community-notes/statuses?target_ref=#{target["entity_id"]}")

    assert listing.status == 200
    assert [listed] = Jason.decode!(listing.resp_body)["statuses"]
    assert listed["note_id"] == note["entity_id"]
    assert listed["status"] == "helpful"
  end

  test "ten basic raters can establish not-helpful consensus" do
    {_author, _author_key, _target, note} = create_note()

    Enum.each(1..10, fn index ->
      {did, key} = identity("not-helpful-#{index}")
      assert rate(note["entity_id"], did, key, "not_helpful", ["incorrect"]).status == 201
    end)

    result = status(note)
    assert result["status"] == "not_helpful"
    assert result["score"] == 0.0
    assert result["verified_human_count"] == 0
  end

  test "critical quality tags block helpful status and mixed votes become disputed" do
    {_author, _author_key, _target, note} = create_note()

    levels = ["helpful", "helpful", "helpful", "somewhat_helpful", "not_helpful"]

    Enum.with_index(levels, 1)
    |> Enum.each(fn {level, index} ->
      tier = if index <= 2, do: "verified_human", else: "basic"
      {did, key} = identity("disputed-#{index}", tier)
      tags = if level == "helpful", do: ["good_sources"], else: ["incorrect"]
      assert rate(note["entity_id"], did, key, level, tags).status == 201
    end)

    result = status(note)
    assert result["score"] == 0.7
    assert result["status"] == "disputed"

    {_author2, _key2, _target2, note2} = create_note()

    Enum.each(1..5, fn index ->
      tier = if index <= 2, do: "verified_human", else: "basic"
      {did, key} = identity("critical-#{index}", tier)
      tags = if index <= 2, do: ["good_sources", "incorrect"], else: ["good_sources"]
      assert rate(note2["entity_id"], did, key, "helpful", tags).status == 201
    end)

    assert status(note2)["status"] == "disputed"
  end

  test "target edits and note withdrawal produce explicit terminal statuses" do
    {author, author_key, target, note} = create_note()
    {rater, rater_key} = identity("state-rater")
    assert rate(note["entity_id"], rater, rater_key, "helpful", ["good_sources"]).status == 201

    target_update =
      build_op(author, author_key, "murmur", target["entity_id"], "update", %{
        "body" => "A revised public claim",
        "visibility" => "public"
      })

    assert post_json("/api/v1/ops", target_update).status == 202
    assert status(note)["status"] == "target_changed"

    delete =
      build_op(author, author_key, "context_note", note["entity_id"], "delete", %{
        "deletedAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    assert post_json("/api/v1/ops", delete).status == 202
    assert status(note)["status"] == "withdrawn"
  end

  test "enforces tier-aware rating rate limits" do
    original = Application.get_env(:ansible_relay, :community_notes_rating_limits)

    Application.put_env(:ansible_relay, :community_notes_rating_limits, %{
      "basic" => %{capacity: 1, refill_per_second: 0.0, suspension_ms: 60_000}
    })

    on_exit(fn -> restore_env(:community_notes_rating_limits, original) end)
    RateLimiter.reset()

    {_a1, _k1, _t1, note1} = create_note()
    {_a2, _k2, _t2, note2} = create_note()
    {rater, key} = identity("limited")

    assert rate(note1["entity_id"], rater, key, "helpful", ["good_sources"]).status == 201
    limited = rate(note2["entity_id"], rater, key, "helpful", ["good_sources"])
    assert limited.status == 429
    assert Jason.decode!(limited.resp_body)["detail"]["retry_after_ms"] == 60_000

    assert Metrics.render() =~
             ~s(community_notes_rating_rate_limited_total{tier="basic"} 1)
  end

  defp create_note do
    {author, author_key} = identity("author")

    target =
      build_op(author, author_key, "murmur", unique("target"), "insert", %{
        "body" => "A public claim",
        "visibility" => "public",
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    assert post_json("/api/v1/ops", target).status == 202

    note =
      build_op(author, author_key, "context_note", unique("context-note"), "insert", %{
        "targetEntityType" => "murmur",
        "targetEntityId" => target["entity_id"],
        "targetOpId" => target["op_id"],
        "targetContentHash" => target_hash(target),
        "body" => "An official source provides additional context.",
        "sources" => [%{"url" => "https://example.test/source", "title" => "Source"}],
        "visibility" => "public",
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    assert post_json("/api/v1/ops", note).status == 202
    {author, author_key, target, note}
  end

  defp identity(label, tier \\ "basic") do
    did = "did:key:z6MkCommunity#{label}#{System.unique_integer([:positive])}"
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    public_key_hex = Base.encode16(public_key, case: :lower)
    :ok = IdentityCache.put(did, public_key_hex, unique("identity-nullifier"))

    :ok =
      DidAccountCache.put(did, public_key_hex, unique("community-handle"), reputation_tier: tier)

    {did, private_key}
  end

  defp rate(note_id, did, private_key, level, tags) do
    intent = rating_intent(note_id, did, private_key, level, tags)
    post_json("/api/v1/forum-host/community-notes/#{note_id}/ratings", intent)
  end

  defp rating_intent(note_id, did, private_key, level, tags) do
    now = DateTime.utc_now()

    intent = %{
      "type" => "io.trisaura.forum.rateContextNote",
      "version" => 1,
      "intent_id" => unique("rating-intent"),
      "author_did" => did,
      "target_forum_host" => "http://localhost:4001",
      "action" => "rate_context_note",
      "created_at" => DateTime.to_iso8601(now),
      "expires_at" => DateTime.to_iso8601(DateTime.add(now, 300, :second)),
      "note_id" => note_id,
      "level" => level,
      "tags" => tags
    }

    Map.put(intent, "signature", sign(private_key, SignedIntent.canonical_json(intent)))
  end

  defp status(note) do
    response = get_json("/api/v1/forum-host/community-notes/#{note["entity_id"]}/status")
    assert response.status == 200
    Jason.decode!(response.resp_body)["status"]
  end

  defp rating_path(note),
    do: "/api/v1/forum-host/community-notes/#{note["entity_id"]}/ratings"

  defp build_op(did, private_key, entity_type, entity_id, op_type, payload) do
    op = %{
      "op_id" => unique("op"),
      "author_did" => did,
      "entity_type" => entity_type,
      "entity_id" => entity_id,
      "op_type" => op_type,
      "payload" => Base.encode64(Jason.encode!(payload))
    }

    Map.put(op, "signature", sign(private_key, op_signing_payload(op)))
  end

  defp op_signing_payload(op) do
    op
    |> Map.take(~w(author_did entity_id entity_type op_id op_type payload))
    |> SignedIntent.canonical_json()
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp target_hash(target) do
    {:ok, raw} = Base.decode64(target["payload"])
    payload = Jason.decode!(raw)

    "sha256:" <>
      (:crypto.hash(:sha256, SignedIntent.canonical_json(payload))
       |> Base.encode16(case: :lower))
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp get_json(path), do: conn(:get, path) |> Router.call(@router_opts)
  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
