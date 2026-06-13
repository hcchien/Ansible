defmodule AnsibleAppview.IngestVerificationTest do
  @moduledoc """
  Phase 2 item 1 (SOSP D-1): the AppView independently re-verifies every op's
  Ed25519 signature (and, when carried, the author DID anchor expiry) before
  folding into public projections. These tests assert the trust boundary:
  validly-signed ops fold and surface in reads with provenance; forged ops are
  excluded from every public read and counted in the rejection metric; an
  expired-anchor op (anchor expiry plumbed through the op) is likewise excluded.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias AnsibleAppview.Ingest.Folder
  alias AnsibleAppview.{Discovery, Metrics, Repo, SigningPayload, Timeline}
  alias AnsibleAppview.Db.FeedItem

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleAppview.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleAppview.Repo, {:shared, self()})

    case Metrics.start_link(poll_interval_ms: 0) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  # --- helpers (mirror ingest_timeline_test / metrics_test) ---

  defp keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp signed_op(opts) do
    priv = Keyword.fetch!(opts, :priv)

    base = %{
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

    op =
      case Keyword.get(opts, :anchor_expires_at) do
        nil -> base
        value -> Map.put(base, "anchor_expires_at", value)
      end

    signature =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [priv, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", signature)
  end

  defp rejection_count(reason) do
    body = Metrics.render()

    case Regex.run(
           ~r/appview_ingest_rejections_total\{reason="#{reason}"\}\s+(\d+)/,
           body
         ) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
  end

  test "a validly-signed op folds with sig_verified=true and appears in reads" do
    {pub, priv} = keypair()

    op =
      signed_op(
        log_id: 100,
        author_did: "did:key:valid",
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        reputation_tier: "verified_human",
        payload: %{"mode" => "murmur", "body" => "real", "visibility" => "public"}
      )

    {indexed, max_log} = Folder.apply_ops([op])
    assert indexed == 1
    assert max_log == 100

    # Row persisted with verification provenance.
    row = Repo.one(from(f in FeedItem, where: f.log_id == 100))
    assert row.sig_verified == true
    assert row.source == "relay_firehose"
    assert %DateTime{} = row.verified_at
    assert row.signature == op["signature"]
    # No anchor expiry was carried, so it is left nil (see Folder TODO).
    assert is_nil(row.anchor_expires_at)

    # Surfaces in author timeline and the global explore feed.
    timeline = Timeline.for_authors(["did:key:valid"], nil, 50)
    assert Enum.map(timeline.items, & &1.op_id) == ["op-100"]

    explore = Discovery.explore(nil, 50)
    assert "op-100" in Enum.map(explore.items, & &1.op_id)
  end

  test "a bad-signature op is excluded from public reads and increments the rejection metric" do
    {pub, priv} = keypair()
    {_otherpub, otherpriv} = keypair()
    before = rejection_count("bad_signature")

    forged =
      signed_op(
        log_id: 101,
        author_did: "did:key:mallory",
        entity_type: "murmur",
        # signed with otherpriv but claims pub -> signature does not verify
        pub: pub,
        priv: otherpriv,
        payload: %{"mode" => "murmur", "body" => "forged", "visibility" => "public"}
      )

    {indexed, _max_log} = Folder.apply_ops([forged])
    assert indexed == 0

    # Never written to the projection at all.
    assert Repo.one(from(f in FeedItem, where: f.log_id == 101)) == nil

    # Excluded from every public read.
    assert Timeline.for_authors(["did:key:mallory"], nil, 50).items == []
    assert "op-101" not in Enum.map(Discovery.explore(nil, 50).items, & &1.op_id)

    # Counted under reason=bad_signature.
    assert rejection_count("bad_signature") == before + 1
  end

  test "read path excludes a row whose sig_verified=false (defense-in-depth)" do
    {pub, _priv} = keypair()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    # Simulate a row reaching the table without verification (e.g. a future
    # second ingest path or a bug). The public read must still hide it.
    Repo.insert_all(FeedItem, [
      %{
        log_id: 102,
        op_id: "op-102",
        author_did: "did:key:unverified",
        entity_type: "murmur",
        entity_id: "e-102",
        op_type: "insert",
        board_id: nil,
        thread_id: nil,
        visibility: "public",
        item_created_at: now,
        payload: %{"mode" => "murmur", "body" => "x", "visibility" => "public"},
        public_key_hex: pub,
        author_tier: "basic",
        deleted: false,
        sig_verified: false,
        source: "relay_firehose",
        verified_at: nil,
        signature: nil,
        anchor_expires_at: nil,
        inserted_at: now,
        updated_at: now
      }
    ])

    assert Timeline.for_authors(["did:key:unverified"], nil, 50).items == []
    assert "op-102" not in Enum.map(Discovery.explore(nil, 50).items, & &1.op_id)
  end

  test "an expired-anchor op is excluded and counted (anchor expiry plumbed)" do
    {pub, priv} = keypair()
    before = rejection_count("expired_anchor")

    expired =
      signed_op(
        log_id: 103,
        author_did: "did:key:expired",
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        # anchor expired yesterday — signature is valid, anchor is not
        anchor_expires_at: "2026-06-12T00:00:00Z",
        payload: %{"mode" => "murmur", "body" => "stale anchor", "visibility" => "public"}
      )

    {indexed, _max_log} = Folder.apply_ops([expired])
    assert indexed == 0

    assert Repo.one(from(f in FeedItem, where: f.log_id == 103)) == nil
    assert Timeline.for_authors(["did:key:expired"], nil, 50).items == []
    assert rejection_count("expired_anchor") == before + 1
  end

  test "a non-expired-anchor op folds and persists the anchor expiry" do
    {pub, priv} = keypair()

    op =
      signed_op(
        log_id: 104,
        author_did: "did:key:fresh",
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        anchor_expires_at: "2099-01-01T00:00:00Z",
        payload: %{"mode" => "murmur", "body" => "fresh anchor", "visibility" => "public"}
      )

    {indexed, _max_log} = Folder.apply_ops([op])
    assert indexed == 1

    row = Repo.one(from(f in FeedItem, where: f.log_id == 104))
    assert row.sig_verified == true
    assert %DateTime{} = row.anchor_expires_at
  end
end
