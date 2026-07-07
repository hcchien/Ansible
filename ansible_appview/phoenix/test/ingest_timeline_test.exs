defmodule AnsibleAppview.IngestTimelineTest do
  use ExUnit.Case, async: false

  alias AnsibleAppview.Ingest.Folder
  alias AnsibleAppview.{SigningPayload, Timeline}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleAppview.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleAppview.Repo, {:shared, self()})
    :ok
  end

  defp keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp signed_op(opts) do
    priv = Keyword.fetch!(opts, :priv)

    op = %{
      "log_id" => Keyword.fetch!(opts, :log_id),
      "op_id" => Keyword.get(opts, :op_id, "op-#{Keyword.fetch!(opts, :log_id)}"),
      "author_did" => Keyword.fetch!(opts, :author_did),
      "entity_type" => Keyword.fetch!(opts, :entity_type),
      "entity_id" => Keyword.get(opts, :entity_id, "e-#{Keyword.fetch!(opts, :log_id)}"),
      "op_type" => Keyword.get(opts, :op_type, "insert"),
      "payload" => Base.encode64(Jason.encode!(Keyword.get(opts, :payload, %{}))),
      "public_key_hex" => Keyword.fetch!(opts, :pub),
      "reputation_tier" => Keyword.get(opts, :reputation_tier, "basic"),
      "received_at" => "2026-06-05T00:00:00Z"
    }

    signature =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [priv, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", signature)
  end

  test "folds valid public ops, skips invalid sig and private, serves timeline" do
    {pub, priv} = keypair()
    {_otherpub, otherpriv} = keypair()

    ops = [
      signed_op(
        log_id: 0,
        op_id: "profile-alice",
        author_did: "did:key:alice",
        entity_type: "profile",
        pub: pub,
        priv: priv,
        payload: %{
          "visibility" => "public",
          "handle" => "alice.elix.cool",
          "displayName" => "Alice"
        }
      ),
      signed_op(
        log_id: 1,
        author_did: "did:key:alice",
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        reputation_tier: "verified_human",
        payload: %{"mode" => "murmur", "body" => "hello", "visibility" => "public"}
      ),
      # private note -> skipped
      signed_op(
        log_id: 2,
        author_did: "did:key:alice",
        entity_type: "note",
        pub: pub,
        priv: priv,
        payload: %{"mode" => "note", "body" => "secret", "visibility" => "private"}
      ),
      # invalid signature: signed with a different key than public_key_hex
      signed_op(
        log_id: 3,
        author_did: "did:key:mallory",
        entity_type: "murmur",
        pub: pub,
        priv: otherpriv,
        payload: %{"mode" => "murmur", "body" => "forged", "visibility" => "public"}
      ),
      # a post in a board (no visibility) -> indexed
      signed_op(
        log_id: 4,
        author_did: "did:key:bob",
        entity_type: "post",
        pub: pub,
        priv: priv,
        payload: %{"boardId" => "board-1", "threadId" => "t-1", "content" => "hi"}
      ),
      # a comment on content -> indexed, but kept OUT of top-level feeds
      signed_op(
        log_id: 5,
        author_did: "did:key:bob",
        entity_type: "comment",
        pub: pub,
        priv: priv,
        payload: %{"targetId" => "t-1", "threadId" => "t-1", "content" => "a comment"}
      )
    ]

    {indexed, max_log} = Folder.apply_ops(ops)
    assert indexed == 3
    assert max_log == 5

    # Timeline for alice returns only her public murmur.
    alice = Timeline.for_authors(["did:key:alice"], nil, 50)
    assert length(alice.items) == 1
    assert hd(alice.items).author_did == "did:key:alice"
    assert hd(alice.items).author_handle == "alice.elix.cool"
    assert hd(alice.items).public_key_hex == pub
    assert hd(alice.items).reputation_tier == "verified_human"

    # Board feed returns bob's post — the comment is NOT a top-level feed item.
    board = Timeline.for_board("board-1", nil, 50)
    assert Enum.map(board.items, & &1.entity_id) == ["e-4"]

    # The comment never leaks into a followed user's timeline either.
    bob = Timeline.for_authors(["did:key:bob"], nil, 50)
    assert Enum.map(bob.items, & &1.entity_id) == ["e-4"]

    # Thread feed DOES include the comment (it is the comments read path), plus
    # any forum post sharing the thread id.
    thread = Timeline.for_thread("t-1", nil, 50)
    assert Enum.sort(Enum.map(thread.items, & &1.entity_id)) == ["e-4", "e-5"]

    # (follow-graph folding is covered by the dedicated test below)

    # Re-folding the same ops is idempotent.
    {reindexed, _} = Folder.apply_ops(ops)
    assert reindexed == 3
    again = Timeline.for_authors(["did:key:alice"], nil, 50)
    assert length(again.items) == 1
  end

  test "folds federated follow ops into the graph; localOnly ignored; delete removes" do
    {pub, priv} = keypair()

    follow = fn log_id, op_type, target, visibility ->
      signed_op(
        log_id: log_id,
        op_id: "follow-#{log_id}",
        author_did: "did:key:reader",
        entity_type: "follow",
        op_type: op_type,
        pub: pub,
        priv: priv,
        payload: %{"targetDid" => target, "visibility" => visibility}
      )
    end

    AnsibleAppview.Ingest.Folder.apply_ops([
      follow.(1, "insert", "did:key:alice", "federated"),
      follow.(2, "insert", "did:key:secret", "localOnly")
    ])

    assert AnsibleAppview.FollowGraph.followers("did:key:alice") == ["did:key:reader"]
    # localOnly follow is never indexed.
    assert AnsibleAppview.FollowGraph.followers("did:key:secret") == []
    assert AnsibleAppview.FollowGraph.following("did:key:reader") == ["did:key:alice"]
    assert AnsibleAppview.FollowGraph.follower_count("did:key:alice") == 1

    # Unfollow (delete) removes the edge.
    AnsibleAppview.Ingest.Folder.apply_ops([follow.(3, "delete", "did:key:alice", "federated")])
    assert AnsibleAppview.FollowGraph.followers("did:key:alice") == []
  end

  test "fan-out on write materializes a reader's home timeline" do
    {pub, priv} = keypair()
    reader = "did:key:fanreader"
    author = "did:key:fanauthor"

    # reader follows author (federated), then author posts a public murmur.
    Folder.apply_ops([
      signed_op(
        log_id: 9001,
        op_id: "follow-9001",
        author_did: reader,
        entity_type: "follow",
        pub: pub,
        priv: priv,
        payload: %{"targetDid" => author, "visibility" => "federated"}
      )
    ])

    Folder.apply_ops([
      signed_op(
        log_id: 9002,
        op_id: "murmur-9002",
        author_did: author,
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        payload: %{"mode" => "murmur", "body" => "fanned out", "visibility" => "public"}
      )
    ])

    home = Timeline.home(reader, nil, 50)
    assert Enum.map(home.items, & &1.op_id) == ["murmur-9002"]
    assert hd(home.items).author_did == author

    # A reader who follows nobody and was never fanned out gets an empty home.
    cold = Timeline.home("did:key:nobody-home", nil, 50)
    assert cold.items == []
  end
end
