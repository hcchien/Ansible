defmodule AnsibleAppview.IngestResilienceTest do
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

    sig =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [priv, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", sig)
  end

  defp approved_follow_grant(request_op_id, follower, author) do
    %{
      "requestOpId" => request_op_id,
      "followerDid" => follower,
      "targetDid" => author,
      "credential" => %{
        "type" => ["VerifiableCredential", "FollowGrantCredential"],
        "issuer" => author,
        "credentialSubject" => %{
          "id" => follower,
          "targetDid" => author,
          "relationship" => "approved_follower"
        }
      }
    }
  end

  test "a poison op is skipped (dead-lettered) and does NOT halt the rest of the page" do
    {pub, priv} = keypair()

    good =
      signed_op(
        log_id: 1,
        author_did: "did:key:alice-poison",
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        payload: %{"body" => "ok", "visibility" => "public"}
      )

    # A structurally-broken op: non-map/garbage values that make preparation
    # raise. `public_key_hex` as an integer trips SigVerifier's guard path, but
    # to be sure we hit the guarded prepare path we feed a value that breaks
    # canonicalization/verification without a valid signature.
    poison = %{
      "log_id" => 2,
      "op_id" => "op-poison",
      "author_did" => "did:key:mallory",
      "entity_type" => "murmur",
      "entity_id" => "e-2",
      "op_type" => "insert",
      "payload" => %{"body" => "x"},
      # a self-referential / unusual public key + missing signature -> rejected
      "public_key_hex" => "not-hex",
      "signature" => "also-not-hex"
    }

    good2 =
      signed_op(
        log_id: 3,
        author_did: "did:key:alice-poison",
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        payload: %{"body" => "ok2", "visibility" => "public"}
      )

    # Must not raise; the two good ops fold, the poison one is dropped.
    {indexed, max_log} = Folder.apply_ops([good, poison, good2])
    assert indexed == 2
    assert max_log == 3

    tl = Timeline.for_authors(["did:key:alice-poison"], nil, 50)
    assert Enum.map(tl.items, & &1.op_id) |> Enum.sort() == ["op-1", "op-3"]
  end

  test "batched cold-read returns items for multiple authors in one shot" do
    {pub, priv} = keypair()

    authors = for i <- 1..3, do: "did:key:batch-#{i}-#{System.unique_integer([:positive])}"

    ops =
      authors
      |> Enum.with_index()
      |> Enum.map(fn {did, idx} ->
        signed_op(
          log_id: 5000 + idx,
          op_id: "batch-op-#{idx}",
          author_did: did,
          entity_type: "murmur",
          pub: pub,
          priv: priv,
          payload: %{"body" => "hi #{idx}", "visibility" => "public"}
        )
      end)

    Folder.apply_ops(ops)

    result = Timeline.for_authors(authors, nil, 50)
    got = Enum.map(result.items, & &1.op_id) |> Enum.sort()
    assert got == ["batch-op-0", "batch-op-1", "batch-op-2"]
    # newest-first ordering preserved
    assert Enum.map(result.items, & &1.log_id) == [5002, 5001, 5000]
  end

  test "a new follow backfills the follower's materialized home timeline with existing posts" do
    {pub, priv} = keypair()
    reader = "did:key:backfill-reader-#{System.unique_integer([:positive])}"
    author = "did:key:backfill-author-#{System.unique_integer([:positive])}"

    # Author posts BEFORE the reader follows.
    Folder.apply_ops([
      signed_op(
        log_id: 7001,
        op_id: "pre-7001",
        author_did: author,
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        payload: %{"body" => "old post", "visibility" => "public"}
      )
    ])

    # Reader was never fanned out, but has a materialized (non-empty) timeline
    # from some other author so it is NOT on the cold-read path.
    AnsibleAppview.HomeTimeline.add(reader, 1, "seed-op")

    # The request does not create a feed edge; the author's signed grant does
    # and must backfill posts that predate the approval.
    Folder.apply_ops([
      signed_op(
        log_id: 7002,
        op_id: "follow-7002",
        author_did: reader,
        entity_type: "follow",
        pub: pub,
        priv: priv,
        payload: %{"targetDid" => author, "visibility" => "federated"}
      ),
      signed_op(
        log_id: 7003,
        op_id: "grant-7003",
        author_did: author,
        entity_type: "follow_grant",
        pub: pub,
        priv: priv,
        payload: approved_follow_grant("follow-7002", reader, author)
      )
    ])

    entries = AnsibleAppview.HomeTimeline.range(reader, nil, 50)
    assert "pre-7001" in Enum.map(entries, & &1.op_id)
  end
end
