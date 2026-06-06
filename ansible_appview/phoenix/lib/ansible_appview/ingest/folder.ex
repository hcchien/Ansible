defmodule AnsibleAppview.Ingest.Folder do
  @moduledoc """
  Folds relay ops into the `feed_items` projection. Re-verifies every op's
  Ed25519 signature (double verification) and only indexes public/unlisted
  content. Idempotent by `log_id`, so re-folding an overlapping range is safe.
  """

  alias AnsibleAppview.{Cache, FollowGraph, HomeTimeline, Repo, SigVerifier, SigningPayload}
  alias AnsibleAppview.Db.FeedItem

  @content_types ~w(murmur note)
  @relayable ~w(public unlisted)

  @doc "Folds a list of relay op maps. Returns {indexed_count, max_log_id}."
  @spec apply_ops([map()]) :: {non_neg_integer(), integer() | nil}
  def apply_ops(ops) when is_list(ops) do
    # Ed25519 verification is CPU-bound and independent per op, so verify the
    # whole page in parallel across schedulers before the sequential DB upserts.
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
      Enum.reduce(prepared, nil, fn {op, _payload, _ok?}, acc ->
        max_int(acc, op["log_id"])
      end)

    # Follow ops update the follow graph; profile ops update the actor directory.
    # Neither belongs in feed_items.
    for {op, payload, verified?} <- prepared, verified? do
      case op["entity_type"] do
        "follow" -> fold_follow(op, payload)
        "profile" -> fold_profile(op, payload)
        _ -> :noop
      end
    end

    rows =
      prepared
      |> Enum.filter(fn {op, payload, verified?} ->
        verified? and op["entity_type"] not in ["follow", "profile"] and
          visibility_ok?(op["entity_type"], payload)
      end)
      |> Enum.map(fn {op, payload, _} -> row(op, payload) end)
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

  defp verify(op) do
    pk = op["public_key_hex"]
    sig = op["signature"]

    is_binary(pk) and is_binary(sig) and
      SigVerifier.verify_ed25519(pk, SigningPayload.build(op), sig)
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

  defp row(op, payload) do
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
