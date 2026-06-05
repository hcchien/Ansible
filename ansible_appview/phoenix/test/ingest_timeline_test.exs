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
      )
    ]

    {indexed, max_log} = Folder.apply_ops(ops)
    assert indexed == 2
    assert max_log == 4

    # Timeline for alice returns only her public murmur.
    alice = Timeline.for_authors(["did:key:alice"], nil, 50)
    assert length(alice.items) == 1
    assert hd(alice.items).author_did == "did:key:alice"
    assert hd(alice.items).public_key_hex == pub
    assert hd(alice.items).reputation_tier == "verified_human"

    # Board feed returns bob's post.
    board = Timeline.for_board("board-1", nil, 50)
    assert Enum.map(board.items, & &1.entity_id) == ["e-4"]

    # Re-folding the same ops is idempotent.
    {reindexed, _} = Folder.apply_ops(ops)
    assert reindexed == 2
    again = Timeline.for_authors(["did:key:alice"], nil, 50)
    assert length(again.items) == 1
  end
end
