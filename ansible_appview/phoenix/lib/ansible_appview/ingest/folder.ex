defmodule AnsibleAppview.Ingest.Folder do
  @moduledoc """
  Folds relay ops into the `feed_items` projection.

  Defense-in-depth (Phase 2 / SOSP D-1): the AppView does **not** trust the
  relay's ingest-time signature check. It independently re-verifies every op's
  Ed25519 signature over the same canonical bytes the app/relay signed
  (`SigningPayload.build/1`, byte-identical to the relay's
  `OpsController.signing_payload/1` — the six sorted keys `author_did`,
  `entity_id`, `entity_type`, `op_id`, `op_type`, `payload`, with
  `schema_version`/`signature` excluded so signatures stay valid), and requires
  a non-expired author DID anchor, before folding an op into a public
  projection. Ops that fail either check are dropped (never written) and counted
  in `appview_ingest_rejections_total{reason}`.

  Only verified, public/unlisted content reaches `feed_items`; folded rows carry
  `sig_verified=true` plus verification provenance (verified_at, source, the
  original signature, and the anchor expiry when known). Idempotent by `log_id`,
  so re-folding an overlapping range is safe.

  Anchor-expiry status: the relay op delta does not yet carry the author's DID
  anchor expiry (`OpsController.attach_public_key/1` adds only `public_key_hex`
  and `reputation_tier`). The expiry check is fully plumbed here — if/when the
  firehose carries `anchor_expires_at` it is enforced and persisted — but until
  then no op can be rejected for an expired anchor (see `anchor_ok?/1` TODO).
  """

  @source "relay_firehose"

  alias AnsibleAppview.{Cache, FollowGraph, HomeTimeline, Repo, SigVerifier, SigningPayload}
  alias AnsibleAppview.Db.FeedItem

  @content_types ~w(murmur note)
  @relayable ~w(public unlisted)

  @doc "Folds a list of relay op maps. Returns {indexed_count, max_log_id}."
  @spec apply_ops([map()]) :: {non_neg_integer(), integer() | nil}
  def apply_ops(ops) when is_list(ops) do
    # Ed25519 verification is CPU-bound and independent per op, so verify the
    # whole page in parallel across schedulers before the sequential DB upserts.
    # Each entry is {op, decoded_payload, verification}, where verification is
    # {:ok, anchor_expires_at} | {:error, :bad_signature | :expired_anchor}.
    prepared =
      ops
      |> Task.async_stream(
        fn op -> {op, decode_payload(op["payload"]), verify(op)} end,
        max_concurrency: System.schedulers_online(),
        ordered: true,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    max_log =
      Enum.reduce(prepared, nil, fn {op, _payload, _verification}, acc ->
        max_int(acc, op["log_id"])
      end)

    # Reason-coded rejection metric: an op failing independent verification is
    # never folded into any public projection (timeline/discovery/follow/
    # profile). Counted so the Phase 2 exit criterion — "public fold rejects bad
    # signatures with reason-coded metrics" — is measurable.
    record_rejections(prepared)

    # Follow ops update the follow graph; profile ops update the actor directory.
    # Neither belongs in feed_items. Only verified ops fold.
    for {op, payload, {:ok, _expires}} <- prepared do
      case op["entity_type"] do
        "follow" -> fold_follow(op, payload)
        "profile" -> fold_profile(op, payload)
        _ -> :noop
      end
    end

    rows =
      prepared
      |> Enum.filter(fn {op, payload, verification} ->
        match?({:ok, _}, verification) and op["entity_type"] not in ["follow", "profile"] and
          visibility_ok?(op["entity_type"], payload)
      end)
      |> Enum.map(fn {op, payload, {:ok, expires_at}} -> row(op, payload, expires_at) end)
      # Same log_id can appear once per page; keep the last occurrence.
      |> Enum.uniq_by(& &1.log_id)

    indexed =
      case rows do
        [] ->
          0

        _ ->
          {count, _} =
            Repo.insert_all(FeedItem, rows,
              on_conflict: {:replace_all_except, [:inserted_at]},
              conflict_target: :log_id
            )

          count
      end

    # Fan-out-on-write: push references into followers' home timelines and warm
    # the per-item object cache. Reproducible from feed_items + the graph, so a
    # failure here only costs a fallback to fan-out-on-read, never correctness.
    fan_out(rows)

    # Observability (Phase 0): count signature-valid ops folded into the
    # projection (follows/profiles/feed items alike), the Phase 3 ingest-rate
    # exit metric. The ingest-lag gauge is sampled by Metrics.poll_gauges.
    folded = Enum.count(prepared, fn {_op, _payload, v} -> match?({:ok, _}, v) end)
    if folded > 0, do: AnsibleAppview.Metrics.inc("appview_ingest_folds_total", %{}, folded)

    {indexed, max_log}
  end

  # Materialize newly-folded content into followers' home timelines and the
  # `item:{op_id}` object cache (write-through; tombstone on delete).
  defp fan_out([]), do: :ok

  defp fan_out(rows) do
    Enum.each(rows, fn row ->
      key = "item:" <> row.op_id

      if row.deleted do
        Cache.put(key, :deleted, item_ttl())
      else
        Cache.put(key, read_map(row), item_ttl())
      end
    end)

    content = Enum.reject(rows, & &1.deleted)
    authors = content |> Enum.map(& &1.author_did) |> Enum.uniq()
    counts = FollowGraph.follower_counts(authors)
    threshold = Application.get_env(:ansible_appview, :celebrity_follower_threshold, 10_000)

    # Celebrities are skipped on write and merged in at read time (hybrid).
    entries =
      content
      |> Enum.reject(fn row -> Map.get(counts, row.author_did, 0) >= threshold end)
      |> Enum.flat_map(fn row ->
        row.author_did
        |> FollowGraph.followers()
        |> Enum.map(fn follower -> {follower, row.log_id, row.op_id} end)
      end)

    case entries do
      [] ->
        :ok

      _ ->
        HomeTimeline.add_many(entries)

        entries
        |> Enum.map(fn {reader, _, _} -> reader end)
        |> Enum.uniq()
        |> Enum.each(fn reader -> HomeTimeline.cap(reader, HomeTimeline.max_entries()) end)
    end
  end

  defp item_ttl, do: Application.get_env(:ansible_appview, :item_cache_ttl_ms, 30_000)

  # Same shape as Timeline.to_map/1, built from the insert row (no extra read).
  defp read_map(row) do
    %{
      log_id: row.log_id,
      op_id: row.op_id,
      author_did: row.author_did,
      entity_type: row.entity_type,
      entity_id: row.entity_id,
      op_type: row.op_type,
      board_id: row.board_id,
      thread_id: row.thread_id,
      visibility: row.visibility,
      created_at: row.item_created_at && DateTime.to_iso8601(row.item_created_at),
      payload: row.payload,
      public_key_hex: row.public_key_hex,
      reputation_tier: row.author_tier
    }
  end

  # Independent verification of one op. Returns {:ok, anchor_expires_at} when the
  # signature verifies over the canonical bytes AND the author's DID anchor is
  # non-expired; otherwise {:error, :bad_signature} | {:error, :expired_anchor}.
  # Signature is checked first so an unverifiable op never has its anchor probed.
  defp verify(op) do
    pk = op["public_key_hex"]
    sig = op["signature"]

    cond do
      not (is_binary(pk) and is_binary(sig) and
               SigVerifier.verify_ed25519(pk, SigningPayload.build(op), sig)) ->
        {:error, :bad_signature}

      true ->
        case anchor_ok?(op) do
          {:ok, expires_at} -> {:ok, expires_at}
          :expired -> {:error, :expired_anchor}
        end
    end
  end

  # DID-anchor expiry gate. The relay op delta does not yet carry the author's
  # anchor expiry, so when no expiry is supplied we accept the op (the signature
  # already proves authorship) and leave anchor_expires_at nil.
  #
  # TODO(Phase 2): once the relay's delta carries the author DID anchor expiry
  # (e.g. `anchor_expires_at` alongside `public_key_hex` in
  # OpsController.attach_public_key/1), this check becomes load-bearing and
  # expired-anchor ops will be rejected. The enforcement path below is already
  # wired — only the relay-side field is missing.
  defp anchor_ok?(op) do
    case parse_dt(op["anchor_expires_at"]) do
      nil ->
        {:ok, nil}

      %DateTime{} = expires_at ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, expires_at}
        else
          :expired
        end
    end
  end

  defp record_rejections(prepared) do
    prepared
    |> Enum.reduce(%{}, fn
      {_op, _payload, {:error, reason}}, acc -> Map.update(acc, reason, 1, &(&1 + 1))
      {_op, _payload, {:ok, _}}, acc -> acc
    end)
    |> Enum.each(fn {reason, count} ->
      AnsibleAppview.Metrics.inc(
        "appview_ingest_rejections_total",
        %{reason: Atom.to_string(reason)},
        count
      )
    end)
  end

  defp visibility_ok?(entity_type, payload) when entity_type in @content_types do
    case payload do
      %{"visibility" => v} when is_binary(v) -> v in @relayable
      # murmur has no visibility field; note requires one.
      _ -> entity_type == "murmur"
    end
  end

  defp visibility_ok?(_entity_type, _payload), do: true

  defp fold_follow(op, payload) do
    # Only federated follows are indexed.
    if payload["visibility"] == "federated" do
      follower = op["author_did"]
      author = payload["targetDid"]

      if is_binary(follower) and is_binary(author) and author != "" do
        case op["op_type"] do
          "delete" -> AnsibleAppview.FollowGraph.remove(follower, author)
          _ -> AnsibleAppview.FollowGraph.upsert(follower, author, op["log_id"])
        end
      end
    end
  end

  # Public actor profiles only. A delete op removes the directory entry.
  defp fold_profile(op, payload) do
    did = op["author_did"]

    cond do
      not (is_binary(did) and did != "") ->
        :noop

      op["op_type"] == "delete" ->
        case AnsibleAppview.Profiles.get(did) do
          nil -> :noop
          profile -> Repo.delete(profile)
        end

      payload["visibility"] in [nil, "public"] ->
        AnsibleAppview.Profiles.upsert(
          did,
          %{
            handle: payload["handle"],
            display_name: payload["displayName"],
            bio: payload["bio"],
            avatar_url: payload["avatarUrl"],
            author_tier: op["reputation_tier"] || "basic"
          },
          op["log_id"]
        )

      true ->
        :noop
    end
  end

  defp row(op, payload, anchor_expires_at) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %{
      log_id: op["log_id"],
      op_id: op["op_id"],
      author_did: op["author_did"],
      entity_type: op["entity_type"],
      entity_id: op["entity_id"],
      op_type: op["op_type"],
      board_id: payload["boardId"],
      thread_id: payload["threadId"],
      visibility: payload["visibility"],
      item_created_at:
        parse_dt(payload["publishedAt"] || payload["createdAt"] || op["received_at"]),
      payload: payload,
      public_key_hex: op["public_key_hex"],
      author_tier: op["reputation_tier"] || "basic",
      deleted: op["op_type"] == "delete",
      sig_verified: true,
      # Verification provenance (Phase 2 / SOSP D-1): this row was
      # independently re-verified here, not trusted from the relay.
      source: @source,
      verified_at: now,
      # Retain the original signature so clients/third parties can re-verify
      # without trusting this projection (plan item 2, partial).
      signature: op["signature"],
      anchor_expires_at: anchor_expires_at,
      inserted_at: now,
      updated_at: now
    }
  end

  defp decode_payload(payload) when is_map(payload), do: payload

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = map} ->
        map

      _ ->
        case Base.decode64(payload) do
          {:ok, raw} ->
            case Jason.decode(raw) do
              {:ok, %{} = map} -> map
              _ -> %{}
            end

          :error ->
            %{}
        end
    end
  end

  defp decode_payload(_), do: %{}

  defp parse_dt(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      # insert_all requires usec precision for :utc_datetime_usec columns, so
      # force the microsecond precision to 6 (from_iso8601 may yield precision 0).
      {:ok, dt, _} -> %{dt | microsecond: {elem(dt.microsecond, 0), 6}}
      _ -> nil
    end
  end

  defp parse_dt(_), do: nil

  defp max_int(nil, b), do: b
  defp max_int(a, nil), do: a
  defp max_int(a, b), do: max(a, b)
end
