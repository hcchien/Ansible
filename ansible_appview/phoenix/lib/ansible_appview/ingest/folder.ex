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

  alias AnsibleAppview.{
    Cache,
    FollowGraph,
    HomeTimeline,
    Profiles,
    Repo,
    SigVerifier,
    SigningPayload
  }

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
        fn op -> prepare_op(op) end,
        max_concurrency: System.schedulers_online(),
        ordered: true,
        timeout: 30_000,
        # A single slow/pathological op must NOT crash the whole fold loop.
        # :kill_task returns {:exit, reason} for that element instead of
        # bringing down the caller; we dead-letter it below.
        on_timeout: :kill_task,
        zip_input_on_exit: true
      )
      |> Enum.zip(ops)
      |> Enum.map(fn
        {{:ok, result}, _op} ->
          result

        {{:exit, reason}, op} ->
          # Poison op: skipped (dead-lettered) with a reason-coded metric rather
          # than halting all ingest. It is treated as a rejected op below.
          dead_letter(op, {:exit, reason})
          {op, %{}, {:error, :poison_op}}
      end)

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
        "follow_grant" -> fold_follow_grant(op, payload)
        "profile" -> fold_profile(op, payload)
        _ -> :noop
      end
    end

    # Deletions hide content by entity_id. A delete/removal op carries its own
    # log_id, so it must UPDATE the original content row(s) rather than insert a
    # new row (the old bug: the delete was folded as a fresh deleted=true row
    # while the original stayed deleted=false and was served forever). Covers
    # both signature-verified author deletes and host moderation removals; runs
    # before the insert path, which now excludes deletes.
    apply_deletions(prepared)

    rows =
      prepared
      |> Enum.filter(fn {op, payload, verification} ->
        match?({:ok, _}, verification) and
          op["entity_type"] not in ["follow", "follow_grant", "profile"] and
          op["op_type"] != "delete" and
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
      author_handle: author_handle(row.author_did),
      author_display_name: author_display_name(row.author_did),
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

  defp author_handle(did) when is_binary(did) do
    case Profiles.get(did) do
      %{handle: handle} when is_binary(handle) and handle != "" -> handle
      _ -> nil
    end
  end

  defp author_handle(_did), do: nil

  defp author_display_name(did) when is_binary(did) do
    case Profiles.get(did) do
      %{display_name: display_name} when is_binary(display_name) and display_name != "" ->
        display_name

      _ ->
        nil
    end
  end

  defp author_display_name(_did), do: nil

  # Per-op preparation, guarded so a single malformed op (decode/verify raising)
  # is dead-lettered and skipped rather than crashing the whole page fold. A
  # timeout is handled separately (the task is killed and surfaces as {:exit,_}).
  defp prepare_op(op) do
    {op, decode_payload(op["payload"]), verify(op)}
  rescue
    e ->
      dead_letter(op, {:error, e})
      {op, %{}, {:error, :poison_op}}
  catch
    kind, reason ->
      dead_letter(op, {kind, reason})
      {op, %{}, {:error, :poison_op}}
  end

  # A single malformed/poison op is logged with its id + reason and counted so a
  # stuck ingest is visible, instead of silently halting the drain loop.
  defp dead_letter(op, reason) do
    require Logger

    Logger.error(
      "AppView ingest dead-lettered op " <>
        "log_id=#{inspect(op["log_id"])} op_id=#{inspect(op["op_id"])}: #{inspect(reason)}"
    )

    AnsibleAppview.Metrics.inc("appview_ingest_rejections_total", %{reason: "poison_op"})
  end

  # Independent verification of one op. Returns {:ok, anchor_expires_at} when the
  # signature verifies over the canonical bytes AND the author's DID anchor is
  # non-expired; otherwise {:error, :bad_signature} | {:error, :expired_anchor}.
  # Signature is checked first so an unverifiable op never has its anchor probed.
  defp verify(op) do
    pk = op["public_key_hex"]
    sig = op["signature"]
    payload = decode_payload(op["payload"])

    cond do
      op["removed"] == true ->
        # Host moderation tombstone from our own relay firehose: the relay strips
        # payload + signature, so it cannot (and must not) be verified by author
        # signature. It is honored as a delete-by-entity_id in apply_deletions,
        # never folded as content. Safe within the existing trust boundary: the
        # relay is already this consumer's sole firehose and can withhold any op,
        # so honoring a removal only exercises hide-power it already has — it
        # still cannot forge content (that requires a valid signature below).
        {:error, :moderation_removed}

      web_publication_proof_valid?(op, payload) ->
        case anchor_ok?(op) do
          {:ok, expires_at} -> {:ok, expires_at}
          :expired -> {:error, :expired_anchor}
        end

      not (is_binary(pk) and is_binary(sig) and
               SigVerifier.verify_identity(
                 op["signing_algorithm"] || "ed25519",
                 pk,
                 SigningPayload.build(op),
                 sig
               )) ->
        {:error, :bad_signature}

      true ->
        case anchor_ok?(op) do
          {:ok, expires_at} -> {:ok, expires_at}
          :expired -> {:error, :expired_anchor}
        end
    end
  end

  defp web_publication_proof_valid?(op, payload) when is_map(payload) do
    proof = payload["web_author_proof"]
    operation = payload["web_operation"]
    operation_hash = payload["web_operation_hash"]
    receipt = payload["web_host_receipt"]

    with true <- is_map(proof) and is_map(operation) and is_map(receipt),
         true <- proof["scheme"] == "webauthn-p256-sha256",
         true <- proof["user_present"] == true and proof["user_verified"] == true,
         true <- operation["operation_id"] == op["op_id"],
         true <- operation["author_did"] == op["author_did"],
         true <- operation["entity_type"] == op["entity_type"],
         true <- operation["entity_id"] == op["entity_id"],
         true <- operation_hash == proof["operation_hash"],
         true <- operation_hash == receipt["operation_hash"],
         true <- operation_hash == sha256(canonical_json(operation)),
         true <-
           SigVerifier.verify_ed25519(
             receipt["public_key_hex"],
             operation_hash,
             receipt["signature"]
           ) do
      true
    else
      _ -> false
    end
  end

  defp web_publication_proof_valid?(_op, _payload), do: false

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
      # :poison_op is already counted (and logged) by dead_letter/2; don't double count.
      {_op, _payload, {:error, :poison_op}}, acc -> acc
      # A host removal tombstone is an applied takedown, not a rejected op.
      {_op, _payload, {:error, :moderation_removed}}, acc -> acc
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

  # Mark the original content row(s) deleted for every delete/removal op in the
  # page, keyed by (entity_id, author_did) since a delete op has its own log_id.
  # Author deletes are signature-verified ({:ok, _} + op_type "delete"); host
  # moderation removals arrive as {:error, :moderation_removed}. Both hide by the
  # same mechanism.
  defp apply_deletions(prepared) do
    pairs =
      prepared
      |> Enum.filter(&deletion?/1)
      |> Enum.flat_map(fn {op, _payload, _verification} ->
        entity_id = op["entity_id"]
        author_did = op["author_did"]

        if is_binary(entity_id) and entity_id != "" and is_binary(author_did) and
             author_did != "" do
          [{entity_id, author_did}]
        else
          []
        end
      end)
      |> Enum.uniq()

    case pairs do
      [] -> :ok
      _ -> mark_deleted(pairs)
    end
  end

  defp deletion?({op, _payload, {:ok, _}}),
    do:
      op["entity_type"] not in ["follow", "follow_grant", "profile"] and
        op["op_type"] == "delete"

  defp deletion?({_op, _payload, {:error, :moderation_removed}}), do: true
  defp deletion?(_), do: false

  # Flip deleted=true on the matching not-yet-deleted rows, then tombstone the
  # object cache for each affected op_id and drop the author building-block cache
  # so the removal is visible immediately, not only after the cache TTL lapses.
  # All read paths already filter deleted == false, so this is the whole fix.
  defp mark_deleted(pairs) do
    import Ecto.Query

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    total =
      Enum.reduce(pairs, 0, fn {entity_id, author_did}, acc ->
        {count, op_ids} =
          Repo.update_all(
            from(f in FeedItem,
              where:
                f.entity_id == ^entity_id and f.author_did == ^author_did and
                  f.deleted == false,
              select: f.op_id
            ),
            set: [deleted: true, updated_at: now]
          )

        for op_id <- op_ids || [], do: Cache.put("item:" <> op_id, :deleted, item_ttl())
        Cache.delete("author:" <> author_did)
        acc + count
      end)

    if total > 0, do: AnsibleAppview.Metrics.inc("appview_ingest_deletes_total", %{}, total)
    :ok
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
    # A follow op is a request. It does not create a feed edge until the target
    # signs a matching FollowGrantCredential.
    if payload["visibility"] == "federated" do
      follower = op["author_did"]
      author = payload["targetDid"]

      if is_binary(follower) and is_binary(author) and author != "" do
        case op["op_type"] do
          "delete" ->
            FollowGraph.remove_request(follower, author)
            FollowGraph.remove(follower, author)

          _ ->
            FollowGraph.request(op["op_id"], follower, author, op["log_id"])
        end
      end
    end
  end

  defp fold_follow_grant(op, payload) do
    credential = payload["credential"] || %{}
    subject = credential["credentialSubject"] || %{}
    follower = payload["followerDid"]
    author = payload["targetDid"]
    request_op_id = payload["requestOpId"]

    valid_credential =
      op["op_type"] == "delete" or
        (credential["type"] == ["VerifiableCredential", "FollowGrantCredential"] and
           credential["issuer"] == author and subject["id"] == follower and
           subject["targetDid"] == author and
           subject["relationship"] == "approved_follower")

    if valid_credential and author == op["author_did"] and is_binary(follower) and
         is_binary(request_op_id) and FollowGraph.requested?(request_op_id, follower, author) do
      if subject["relationship"] == "approved_follower" and op["op_type"] != "delete" do
        FollowGraph.upsert(follower, author, op["log_id"])
        backfill_home_timeline(follower, author)
      else
        FollowGraph.remove(follower, author)
      end
    end
  end

  # On a NEW follow edge, backfill the follower's materialized home timeline with
  # the followed author's most-recent EXISTING items. Without this a reader who
  # already has a materialized timeline (past the cold-read fallback) would only
  # ever see the author's FUTURE posts. Bounded to the newest N and skipped for
  # celebrities (handled by read-time merge). Best-effort: the timeline is a
  # reproducible cache, so a failure only degrades to fan-out-on-read.
  defp backfill_home_timeline(follower, author) do
    threshold = Application.get_env(:ansible_appview, :celebrity_follower_threshold, 10_000)
    limit = Application.get_env(:ansible_appview, :follow_backfill_limit, 50)

    if FollowGraph.follower_count(author) < threshold do
      import Ecto.Query

      entries =
        Repo.all(
          from(f in FeedItem,
            where:
              f.author_did == ^author and f.deleted == false and f.sig_verified == true and
                f.entity_type != "comment" and
                (is_nil(f.visibility) or f.visibility in ^@relayable),
            order_by: [desc: f.log_id],
            limit: ^limit,
            select: {f.log_id, f.op_id}
          )
        )
        |> Enum.map(fn {log_id, op_id} -> {follower, log_id, op_id} end)

      case entries do
        [] ->
          :ok

        _ ->
          HomeTimeline.add_many(entries)
          HomeTimeline.cap(follower, HomeTimeline.max_entries())
      end
    end
  rescue
    _ -> :ok
  end

  # Public actor profiles only. A delete op removes the directory entry.
  defp fold_profile(op, payload) do
    # Relay only supplies canonical_author_did for a completed dual-signed
    # migration. Preserve the original DID on content rows, but keep one actor
    # directory entry for the canonical identity.
    did = op["canonical_author_did"] || op["author_did"]

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
            author_tier: op["reputation_tier"] || "basic",
            public_credentials: %{
              "items" => List.wrap(op["public_profile_credentials"])
            }
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
      canonical_author_did: op["canonical_author_did"] || op["author_did"],
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
      source:
        if(get_in(payload, ["web_author_proof", "scheme"]) == "webauthn-p256-sha256",
          do: "forum_host_webauthn_receipt",
          else: @source
        ),
      verified_at: now,
      # Retain the original signature so clients/third parties can re-verify
      # without trusting this projection (plan item 2, partial).
      signature: op["signature"],
      anchor_expires_at: anchor_expires_at,
      inserted_at: now,
      updated_at: now
    }
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)
  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

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
