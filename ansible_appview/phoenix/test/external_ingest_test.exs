defmodule AnsibleAppview.ExternalIngestTest do
  @moduledoc """
  Inbound federation — curated ActivityPub ingest (design 2026-06-13).

  The load-bearing safety property of this slice (Constitution Base Rules 4/6/7,
  Phase 2 integrity): **external content never appears on verified surfaces.**
  Ingested external items carry `sig_verified=false`, so the existing Phase 2 read
  filters (timeline + discovery, which all require `sig_verified == true`) exclude
  them by construction. These tests assert that invariant directly, plus dedup on
  re-poll, HTTP-signature recorded but never verifying, disable/reversibility, and
  fetch-failure tolerance.
  """
  use ExUnit.Case, async: false
  use Plug.Test

  import Ecto.Query

  alias AnsibleAppview.{Discovery, External, ExternalSources, Metrics, Repo, Timeline}
  alias AnsibleAppview.Db.FeedItem
  alias AnsibleAppview.Ingest.{ExternalIngest, Folder}
  alias AnsibleAppview.SigningPayload
  alias AnsibleAppview.Web.Router

  @router_opts Router.init([])

  @actor "https://m.example.test/users/alice"
  @instance "m.example.test"
  @public "https://www.w3.org/ns/activitystreams#Public"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleAppview.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleAppview.Repo, {:shared, self()})

    case Metrics.start_link(poll_interval_ms: 0) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Default: the configured outbox client is a stub returning no items unless a
    # test overrides it. Each test sets its own stub via put_env + on_exit reset.
    prev = Application.get_env(:ansible_appview, :external_outbox_client)
    on_exit(fn -> Application.put_env(:ansible_appview, :external_outbox_client, prev) end)

    :ok
  end

  # --- helpers ---

  # Install a stub OutboxClient that returns `result` for any actor.
  defp stub_outbox(result) do
    me = self()

    stub =
      AnsibleAppview.ExternalIngestTest.StubClient.put(fn actor_uri ->
        send(me, {:fetched, actor_uri})
        result
      end)

    Application.put_env(:ansible_appview, :external_outbox_client, stub)
  end

  defp ap_note(id, opts \\ []) do
    %{
      "type" => "Create",
      "object" => %{
        "id" => id,
        "type" => "Note",
        "attributedTo" => @actor,
        "content" => Keyword.get(opts, :content, "hello from the fediverse"),
        "published" => "2026-06-10T00:00:00Z",
        "to" => [@public]
      }
    }
    |> maybe_sig(opts)
  end

  defp maybe_sig(note, opts) do
    case Keyword.get(opts, :http_sig) do
      nil -> note
      bool -> Map.put(note, "_http_signature_valid", bool)
    end
  end

  defp add_source(attrs \\ %{}) do
    {:ok, source} =
      ExternalSources.add(
        Map.merge(
          %{actor_uri: @actor, instance: @instance, compliance_level: "compatible"},
          attrs
        )
      )

    source
  end

  # A validly-signed native verified op (mirrors ingest_verification_test).
  defp native_verified_op(log_id, did) do
    {pub, priv} = keypair()

    op = %{
      "log_id" => log_id,
      "op_id" => "op-#{log_id}",
      "author_did" => did,
      "entity_type" => "murmur",
      "entity_id" => "e-#{log_id}",
      "op_type" => "insert",
      "payload" =>
        Base.encode64(
          Jason.encode!(%{"mode" => "murmur", "body" => "native", "visibility" => "public"})
        ),
      "public_key_hex" => pub,
      "reputation_tier" => "verified_human",
      "received_at" => "2026-06-05T00:00:00Z"
    }

    sig =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [priv, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", sig)
  end

  defp keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp metric_count(name, label_re \\ "") do
    body = Metrics.render()
    re = Regex.compile!("#{name}#{label_re}\\s+(\\d+)")

    case Regex.run(re, body) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
  end

  # ============================================================================
  # THE CRITICAL INVARIANT
  # ============================================================================

  test "external content NEVER appears on any verified read path; native verified item unaffected" do
    # A native verified item exists and is visible.
    native = native_verified_op(500, "did:key:native")
    {1, _} = Folder.apply_ops([native])

    # Ingest an external item from a curated source.
    source = add_source()
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/1")]})
    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(source)

    # The external row IS persisted, in the external lane, NOT verified.
    ext = Repo.one(from(f in FeedItem, where: f.op_id == "https://m.example.test/notes/1"))
    assert ext.sig_verified == false
    assert ext.source == "activitypub"
    assert ext.author_tier == "external_unverified"
    assert ext.external_actor_uri == @actor
    assert ext.external_instance == @instance
    assert ext.compliance_level == "compatible"

    # Verified timeline read paths: external excluded, native present.
    assert "op-500" in Enum.map(
             Timeline.for_authors(["did:key:native"], nil, 50).items,
             & &1.op_id
           )

    # The external item's "author" is its actor URI; no verified read returns it.
    assert Timeline.for_authors([@actor], nil, 50).items == []

    explore_ops = Enum.map(Discovery.explore(nil, 50).items, & &1.op_id)
    assert "op-500" in explore_ops
    refute "https://m.example.test/notes/1" in explore_ops

    # Discovery search must not surface external content either.
    search_ops = Enum.map(Discovery.search("fediverse", 50).posts, & &1.op_id)
    refute "https://m.example.test/notes/1" in search_ops
  end

  # ============================================================================
  # Per-board external read lane (Task 4b-1) — the ONLY external read path
  # ============================================================================

  defp board_external(board_id, query \\ "") do
    conn(:get, "/api/v1/boards/#{board_id}/external" <> query)
    |> Router.call(@router_opts)
  end

  test "per-board external endpoint returns external items for the mapped board" do
    source = add_source(%{board_id: "board-news"})
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/b1")]})
    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(source)

    # Context layer.
    %{items: items} = External.for_board("board-news", nil, 50)
    assert [item] = items
    assert item.op_id == "https://m.example.test/notes/b1"
    assert item.external == true
    assert item.origin == "activitypub"
    assert item.external_actor_uri == @actor
    assert item.external_instance == @instance
    assert item.compliance_level == "compatible"
    assert item.content == "hello from the fediverse"
    assert item.board_id == "board-news"
    assert is_binary(item.created_at)

    # HTTP layer (response shape + 200).
    resp = board_external("board-news")
    assert resp.status == 200
    body = Jason.decode!(resp.resp_body)
    assert [row] = body["items"]
    assert row["external"] == true
    assert row["origin"] == "activitypub"
    assert row["external_actor_uri"] == @actor
    assert row["compliance_level"] == "compatible"
    assert Map.has_key?(body, "next_cursor")
    assert Map.has_key?(body, "has_more")
  end

  test "per-board external endpoint does NOT return items mapped to a different board" do
    src_a = add_source(%{board_id: "board-a"})
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/a")]})
    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(src_a)

    # A second source, different actor, mapped to a different board. Note id is
    # the dedup key; the source struct (not attributedTo) decides the board_id.
    {:ok, src_b} =
      ExternalSources.add(%{
        actor_uri: "https://m.example.test/users/bob",
        instance: @instance,
        compliance_level: "compatible",
        board_id: "board-b"
      })

    stub_outbox({:ok, [ap_note("https://m.example.test/notes/b")]})
    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(src_b)

    a_ops = Enum.map(External.for_board("board-a", nil, 50).items, & &1.op_id)
    assert "https://m.example.test/notes/a" in a_ops
    refute "https://m.example.test/notes/b" in a_ops

    b_ops = Enum.map(External.for_board("board-b", nil, 50).items, & &1.op_id)
    assert "https://m.example.test/notes/b" in b_ops
    refute "https://m.example.test/notes/a" in b_ops
  end

  test "external items remain absent from timeline and discovery even when board-mapped" do
    # Native verified item is present everywhere it should be.
    native = native_verified_op(700, "did:key:native3")
    {1, _} = Folder.apply_ops([native])

    source = add_source(%{board_id: "board-mixed"})
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/inv")]})
    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(source)

    # Surfaced on its board lane...
    board_ops = Enum.map(External.for_board("board-mixed", nil, 50).items, & &1.op_id)
    assert "https://m.example.test/notes/inv" in board_ops

    # ...but NEVER on verified reads.
    explore_ops = Enum.map(Discovery.explore(nil, 50).items, & &1.op_id)
    refute "https://m.example.test/notes/inv" in explore_ops
    assert "op-700" in explore_ops

    refute "https://m.example.test/notes/inv" in Enum.map(
             Discovery.search("fediverse", 50).posts,
             & &1.op_id
           )

    # The board's verified timeline (sig_verified filter) excludes it too.
    assert Timeline.for_board("board-mixed", nil, 50).items == []
  end

  test "a board with no mapped sources returns an empty external page" do
    # Ingest an external item mapped to a different board so the table is non-empty.
    source = add_source(%{board_id: "board-other"})
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/other")]})
    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(source)

    assert %{items: [], next_cursor: nil, has_more: false} =
             External.for_board("board-empty", nil, 50)

    resp = board_external("board-empty")
    assert resp.status == 200
    body = Jason.decode!(resp.resp_body)
    assert body["items"] == []
  end

  test "per-board external read increments external_read_requests_total{board} for a KNOWN board" do
    # A known board is one with a mapped curated source.
    add_source(%{board_id: "board-metric"})
    before = metric_count("external_read_requests_total", "\\{board=\"board-metric\"\\}")
    assert board_external("board-metric").status == 200

    assert metric_count("external_read_requests_total", "\\{board=\"board-metric\"\\}") ==
             before + 1
  end

  test "an UNKNOWN board does not mint a new metric series (cardinality DoS guard)" do
    bogus = "bogus-#{System.unique_integer([:positive])}"

    # No source maps this board id, so the request must still succeed (empty page)
    # but must NOT create a fresh external_read_requests_total{board=<bogus>} row.
    assert board_external(bogus).status == 200

    assert metric_count("external_read_requests_total", "\\{board=\"#{bogus}\"\\}") == 0
  end

  # ============================================================================
  # Dedup, HTTP-sig, reversibility, failure tolerance
  # ============================================================================

  test "re-polling the same AP object id does not duplicate the row" do
    source = add_source()
    note = ap_note("https://m.example.test/notes/dup")

    stub_outbox({:ok, [note]})
    assert {:ok, %{ingested: 1, deduped: 0}} = ExternalIngest.ingest_source(source)

    # Re-poll: same object id -> one row, counted as a dedup hit.
    stub_outbox({:ok, [note]})
    assert {:ok, %{ingested: 0, deduped: 1}} = ExternalIngest.ingest_source(source)

    count =
      Repo.one(
        from(f in FeedItem,
          where: f.op_id == "https://m.example.test/notes/dup",
          select: count(f.log_id)
        )
      )

    assert count == 1
    assert metric_count("external_ingest_dedup_total") >= 1
  end

  test "HTTP signature validity is recorded but never sets sig_verified" do
    source = add_source()
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/signed", http_sig: true)]})

    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(source)

    row = Repo.one(from(f in FeedItem, where: f.op_id == "https://m.example.test/notes/signed"))
    # Transport-auth status recorded in the payload...
    assert row.payload["http_signature_status"] == "valid"
    # ...but Elix verification stays false. A valid HTTP sig is NOT Elix identity.
    assert row.sig_verified == false
  end

  test "disabling a source hides its content: rows are filterable by source/enabled" do
    source = add_source()
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/rev")]})
    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(source)
    # Consume the fetch message from this first (expected) ingest so the
    # refute below only sees a NEW fetch, not this one.
    assert_received {:fetched, @actor}

    # Disable the source (reversibility lever).
    {:ok, _} = ExternalSources.disable(@actor)
    refute Enum.any?(ExternalSources.list_enabled(), &(&1.actor_uri == @actor))

    # A disabled source is not polled again.
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/rev2")]})
    AnsibleAppview.Ingest.ExternalPoller.poll_all()
    refute_received {:fetched, @actor}

    # And the ingested rows are filterable out by actor_uri (the drop mechanism).
    disabled_uris =
      ExternalSources.list() |> Enum.reject(& &1.enabled) |> Enum.map(& &1.actor_uri)

    remaining =
      Repo.all(
        from(f in FeedItem,
          where: f.source == "activitypub" and f.external_actor_uri not in ^disabled_uris
        )
      )

    assert remaining == []
  end

  test "a source fetch error is tolerated: no crash, error counted, native ingest unaffected" do
    # Native item still folds fine.
    native = native_verified_op(600, "did:key:native2")
    {1, _} = Folder.apply_ops([native])

    source = add_source()
    stub_outbox({:error, :timeout})

    # Returns {:error, _}, does not raise.
    assert {:error, :timeout} = ExternalIngest.ingest_source(source)

    # Counted under the instance.
    assert metric_count("external_source_fetch_errors_total", "\\{instance=\"#{@instance}\"\\}") >=
             1

    # Native verified content still visible.
    assert "op-600" in Enum.map(Discovery.explore(nil, 50).items, & &1.op_id)
  end

  test "ingest_total metric increments by instance on successful ingest" do
    source = add_source()
    before = metric_count("external_ingest_total", "\\{instance=\"#{@instance}\"\\}")
    stub_outbox({:ok, [ap_note("https://m.example.test/notes/metric")]})

    assert {:ok, %{ingested: 1}} = ExternalIngest.ingest_source(source)
    assert metric_count("external_ingest_total", "\\{instance=\"#{@instance}\"\\}") == before + 1
  end

  test "non-public and non-Note items are skipped" do
    source = add_source()

    private_note = %{
      "type" => "Create",
      "object" => %{
        "id" => "https://m.example.test/notes/private",
        "type" => "Note",
        "attributedTo" => @actor,
        "content" => "secret",
        "to" => ["https://m.example.test/users/bob"]
      }
    }

    delete = %{"type" => "Delete", "object" => %{"id" => "x", "type" => "Tombstone"}}

    stub_outbox({:ok, [private_note, delete]})
    assert {:ok, %{ingested: 0}} = ExternalIngest.ingest_source(source)

    assert Repo.one(from(f in FeedItem, where: f.op_id == "https://m.example.test/notes/private")) ==
             nil
  end
end

defmodule AnsibleAppview.ExternalIngestTest.StubClient do
  @moduledoc false
  # A test-only OutboxClient impl: fetch_outbox/1 delegates to a function stashed
  # in application env by the test (no network).
  @behaviour AnsibleAppview.Ingest.External.OutboxClient

  def put(fun) do
    Application.put_env(:ansible_appview, :__stub_outbox_fun__, fun)
    __MODULE__
  end

  @impl true
  def fetch_outbox(actor_uri) do
    fun = Application.fetch_env!(:ansible_appview, :__stub_outbox_fun__)
    fun.(actor_uri)
  end
end
