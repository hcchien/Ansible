defmodule AnsibleAppview.DiscoveryTest do
  use ExUnit.Case, async: false

  alias AnsibleAppview.{Discovery, FollowGraph, SigningPayload}
  alias AnsibleAppview.Ingest.Folder

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleAppview.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleAppview.Repo, {:shared, self()})
    :ok
  end

  test "suggested_follows ranks friends-of-friends above raw popularity and excludes self/known" do
    # reader follows alice. alice follows bob and carol (friends-of-friends).
    FollowGraph.upsert("did:key:reader", "did:key:alice", 1)
    FollowGraph.upsert("did:key:alice", "did:key:bob", 2)
    FollowGraph.upsert("did:key:alice", "did:key:carol", 3)

    # dave is globally popular but not connected to the reader's circle.
    for i <- 1..5, do: FollowGraph.upsert("did:key:fan#{i}", "did:key:dave", 100 + i)

    items = Discovery.suggested_follows("did:key:reader", 10)
    dids = Enum.map(items, & &1.did)

    # Never suggest the reader or someone they already follow.
    refute "did:key:reader" in dids
    refute "did:key:alice" in dids

    # Friends-of-friends are surfaced with a reason + mutual count.
    bob = Enum.find(items, &(&1.did == "did:key:bob"))
    assert bob.reason == "followed_by_people_you_follow"
    assert bob.mutual_count == 1

    # A single mutual outranks dave's raw popularity (mutual_weight = 50 > 5).
    assert Enum.find_index(dids, &(&1 == "did:key:bob")) <
             Enum.find_index(dids, &(&1 == "did:key:dave"))
  end

  test "suggested_follows includes newly published profiles with no follow edges" do
    {pub, priv} = keypair()

    Folder.apply_ops([
      signed_op(pub, priv,
        log_id: 5501,
        op_id: "prof-newcomer",
        author_did: "did:key:newcomer",
        entity_type: "profile",
        payload: %{
          "handle" => "newcomer.elix",
          "displayName" => "Newcomer",
          "visibility" => "public"
        }
      )
    ])

    items = Discovery.suggested_follows("did:key:reader", 20)
    newcomer = Enum.find(items, &(&1.did == "did:key:newcomer"))
    assert newcomer.handle == "newcomer.elix"
    assert newcomer.display_name == "Newcomer"
  end

  test "explore returns public content newest-first, skipping private and deleted" do
    {pub, priv} = keypair()

    Folder.apply_ops([
      signed_op(pub, priv,
        log_id: 5001,
        op_id: "ex-murmur",
        author_did: "did:key:writer",
        entity_type: "murmur",
        payload: %{"mode" => "murmur", "body" => "hello world", "visibility" => "public"}
      ),
      signed_op(pub, priv,
        log_id: 5002,
        op_id: "ex-private",
        author_did: "did:key:writer",
        entity_type: "note",
        payload: %{"mode" => "note", "body" => "secret", "visibility" => "private"}
      ),
      signed_op(pub, priv,
        log_id: 5003,
        op_id: "ex-note",
        author_did: "did:key:writer2",
        entity_type: "note",
        payload: %{"mode" => "note", "body" => "essay", "visibility" => "public"}
      )
    ])

    result = Discovery.explore(nil, 50)
    op_ids = Enum.map(result.items, & &1.op_id)

    # Newest-first, public only; the private note is excluded.
    assert op_ids == ["ex-note", "ex-murmur"]
    refute "ex-private" in op_ids
  end

  test "folds public profile ops and serves people search (handle prefix + name)" do
    {pub, priv} = keypair()

    Folder.apply_ops([
      signed_op(pub, priv,
        log_id: 6001,
        op_id: "prof-alice",
        author_did: "did:key:alice",
        entity_type: "profile",
        payload: %{
          "handle" => "alice.example",
          "displayName" => "Alice Wonder",
          "bio" => "explorer",
          "visibility" => "public"
        }
      ),
      # private profile -> not indexed
      signed_op(pub, priv,
        log_id: 6002,
        op_id: "prof-secret",
        author_did: "did:key:secret",
        entity_type: "profile",
        payload: %{"handle" => "secret.example", "visibility" => "private"}
      )
    ])

    by_handle = AnsibleAppview.Profiles.search("alice", 10)
    assert Enum.map(by_handle, & &1.did) == ["did:key:alice"]
    assert hd(by_handle).display_name == "Alice Wonder"

    # Substring of the display name also matches.
    assert AnsibleAppview.Profiles.search("wonder", 10) |> Enum.map(& &1.did) == ["did:key:alice"]

    # Private profile is never findable.
    assert AnsibleAppview.Profiles.search("secret", 10) == []

    # A later op updates the same directory entry (last write wins).
    Folder.apply_ops([
      signed_op(pub, priv,
        log_id: 6003,
        op_id: "prof-alice-2",
        author_did: "did:key:alice",
        entity_type: "profile",
        payload: %{
          "handle" => "alice.example",
          "displayName" => "Alice Renamed",
          "visibility" => "public"
        }
      )
    ])

    assert AnsibleAppview.Profiles.get("did:key:alice").display_name == "Alice Renamed"
  end

  test "search matches posts (incl. Chinese) and actors by substring, public only" do
    {pub, priv} = keypair()

    Folder.apply_ops([
      signed_op(pub, priv,
        log_id: 7001,
        op_id: "s-en",
        author_did: "did:key:writer",
        entity_type: "murmur",
        payload: %{"mode" => "murmur", "body" => "learning elixir today", "visibility" => "public"}
      ),
      signed_op(pub, priv,
        log_id: 7002,
        op_id: "s-zh",
        author_did: "did:key:writer",
        entity_type: "note",
        payload: %{"mode" => "note", "body" => "今天在學習程式設計", "visibility" => "public"}
      ),
      signed_op(pub, priv,
        log_id: 7003,
        op_id: "s-private",
        author_did: "did:key:writer",
        entity_type: "note",
        payload: %{"mode" => "note", "body" => "private elixir notes", "visibility" => "private"}
      ),
      signed_op(pub, priv,
        log_id: 7004,
        op_id: "s-prof",
        author_did: "did:key:elixirfan",
        entity_type: "profile",
        payload: %{"handle" => "elixirfan.example", "displayName" => "Elixir Fan", "visibility" => "public"}
      )
    ])

    en = Discovery.search("elixir", 20)
    # Public post + the profile match; the private note does not.
    assert Enum.map(en.posts, & &1.op_id) == ["s-en"]
    assert Enum.map(en.actors, & &1.did) == ["did:key:elixirfan"]

    # Chinese substring search works (trigram, no word boundaries needed).
    zh = Discovery.search("學習", 20)
    assert Enum.map(zh.posts, & &1.op_id) == ["s-zh"]
  end

  defp keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp signed_op(pub, priv, opts) do
    op = %{
      "log_id" => Keyword.fetch!(opts, :log_id),
      "op_id" => Keyword.fetch!(opts, :op_id),
      "author_did" => Keyword.fetch!(opts, :author_did),
      "entity_type" => Keyword.fetch!(opts, :entity_type),
      "entity_id" => "e-#{Keyword.fetch!(opts, :log_id)}",
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(Keyword.get(opts, :payload, %{}))),
      "public_key_hex" => pub,
      "reputation_tier" => "basic",
      "received_at" => "2026-06-06T00:00:00Z"
    }

    signature =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [priv, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", signature)
  end
end
