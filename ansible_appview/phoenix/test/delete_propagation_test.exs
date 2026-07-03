defmodule AnsibleAppview.DeletePropagationTest do
  use ExUnit.Case, async: false

  alias AnsibleAppview.Ingest.Folder
  alias AnsibleAppview.{Cache, SigningPayload, Timeline}

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
      "entity_id" => Keyword.fetch!(opts, :entity_id),
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

  defp ids(%{items: items}), do: Enum.map(items, & &1.entity_id)

  test "a signed author delete hides the original murmur from every read path" do
    {pub, priv} = keypair()

    create =
      signed_op(
        log_id: 1,
        op_id: "dp-op1",
        author_did: "did:key:dp-alice",
        entity_type: "murmur",
        entity_id: "dp-m1",
        pub: pub,
        priv: priv,
        payload: %{"mode" => "murmur", "body" => "hello", "visibility" => "public"}
      )

    assert {1, 1} = Folder.apply_ops([create])
    assert "dp-m1" in ids(Timeline.for_authors(["did:key:dp-alice"], nil, 20))

    # The delete op has its own log_id but the same entity_id.
    delete =
      signed_op(
        log_id: 2,
        author_did: "did:key:dp-alice",
        entity_type: "murmur",
        entity_id: "dp-m1",
        op_type: "delete",
        pub: pub,
        priv: priv
      )

    Folder.apply_ops([delete])

    # Author feed, board-independent timeline, and object cache all exclude it.
    refute "dp-m1" in ids(Timeline.for_authors(["did:key:dp-alice"], nil, 20))
    assert {:ok, :deleted} = Cache.get("item:dp-op1")
  end

  test "a comment delete is removed from its thread view" do
    {pub, priv} = keypair()

    create =
      signed_op(
        log_id: 10,
        author_did: "did:key:dp-bob",
        entity_type: "comment",
        entity_id: "dp-c1",
        op_type: "insert",
        pub: pub,
        priv: priv,
        payload: %{"threadId" => "dp-m1", "body" => "nice", "visibility" => "public"}
      )

    Folder.apply_ops([create])
    assert "dp-c1" in ids(Timeline.for_thread("dp-m1", nil, 20))

    delete =
      signed_op(
        log_id: 11,
        author_did: "did:key:dp-bob",
        entity_type: "comment",
        entity_id: "dp-c1",
        op_type: "delete",
        pub: pub,
        priv: priv,
        payload: %{"threadId" => "dp-m1"}
      )

    Folder.apply_ops([delete])
    refute "dp-c1" in ids(Timeline.for_thread("dp-m1", nil, 20))
  end

  test "a host moderation removal tombstone (stripped signature) hides content and is not a rejection" do
    {pub, priv} = keypair()

    create =
      signed_op(
        log_id: 20,
        author_did: "did:key:dp-carol",
        entity_type: "note",
        entity_id: "dp-n1",
        pub: pub,
        priv: priv,
        payload: %{"body" => "reported", "visibility" => "public"}
      )

    Folder.apply_ops([create])
    assert "dp-n1" in ids(Timeline.for_authors(["did:key:dp-carol"], nil, 20))

    # The relay's moderation overlay strips payload + signature and sets removed.
    removal = %{
      "log_id" => 21,
      "op_id" => "dp-op20",
      "author_did" => "did:key:dp-carol",
      "entity_type" => "note",
      "entity_id" => "dp-n1",
      "op_type" => "insert",
      "payload" => nil,
      "signature" => nil,
      "removed" => true,
      "reason_code" => "policy_violation"
    }

    before = rejection_count("bad_signature")
    Folder.apply_ops([removal])

    refute "dp-n1" in ids(Timeline.for_authors(["did:key:dp-carol"], nil, 20))
    # An unsigned removal must NOT inflate the bad-signature rejection metric.
    assert rejection_count("bad_signature") == before
  end

  # Read the current counter value out of the Prometheus render (metric state is
  # process-global, not sandboxed, so compare before/after within one test).
  defp rejection_count(reason) do
    line = ~r/appview_ingest_rejections_total\{reason="#{reason}"\}\s+(\d+)/

    case Regex.run(line, AnsibleAppview.Metrics.render()) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end
end
