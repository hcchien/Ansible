defmodule AnsibleRelay.PublicReads do
  @moduledoc """
  Relay-owned public read model. Reads accepted ops directly through an indexed
  latest-revision view, so there is no Viewer dependency or asynchronous index
  checkpoint. Original signatures and author timestamps remain unchanged.
  Anonymous endpoints never return follow graphs, private/unlisted content or
  protected-board payloads. A direct content link may read unlisted content.
  """
  import Ecto.Query
  alias AnsibleRelay.{Repo, Db.PublicReadItem, OpStore}
  alias AnsibleRelay.Identity.MigrationStore
  alias AnsibleRelay.ForumHost.{PostingGate, Moderation}
  alias AnsibleRelay.Web.Controllers.OpsController

  @top ~w(murmur note thread post)

  def explore(params), do: page(from(r in PublicReadItem, where: r.entity_type in ^@top), params)

  def timeline(dids, params) do
    dids = aliases(dids)

    page(
      from(r in PublicReadItem, where: r.author_did in ^dids and r.entity_type in ^@top),
      params
    )
  end

  def thread(id, params) do
    reply_ids =
      Repo.all(
        from(r in PublicReadItem,
          where:
            r.entity_type in ~w(post comment) and
              (fragment("?->>'threadId'", r.payload) == ^id or
                 fragment("?->>'targetId'", r.payload) == ^id),
          select: r.entity_id
        )
      )

    query =
      from(r in PublicReadItem,
        where:
          r.entity_id == ^id or fragment("?->>'threadId'", r.payload) == ^id or
            fragment("?->>'targetId'", r.payload) == ^id or
            (r.entity_type == "reaction" and fragment("?->>'targetId'", r.payload) in ^reply_ids)
      )

    page(query, params, true)
  end

  def content("item", id) do
    case Repo.one(
           from(r in PublicReadItem,
             where: r.entity_id == ^id and r.entity_type in ^@top,
             order_by: [desc: r.log_id],
             limit: 1
           )
         ) do
      nil -> {:error, :not_found}
      row -> content(row.entity_type, id)
    end
  end

  def content(type, id) when type in @top do
    case Repo.get_by(PublicReadItem, entity_type: type, entity_id: id) do
      nil ->
        {:error, :not_found}

      row ->
        cond do
          row.op_type == "delete" ->
            {:error, :deleted}

          not readable?(row, true) ->
            {:error, :unavailable}

          true ->
            case present(row) do
              nil -> {:error, :unavailable}
              item -> {:ok, decorate(item)}
            end
        end
    end
  end

  def content(_, _), do: {:error, :not_found}

  def profile(did) do
    dids = aliases([did])

    row =
      Repo.one(
        from(r in PublicReadItem,
          where: r.entity_type == "profile" and r.author_did in ^dids,
          order_by: [desc: r.log_id],
          limit: 1
        )
      )

    if row && readable?(row) do
      case present(row) do
        nil -> nil
        item -> actor(item)
      end
    end
  end

  def actors(params) do
    q = search_pattern(params["q"] || "")

    query =
      from(r in PublicReadItem,
        where:
          r.entity_type == "profile" and
            ilike(
              fragment(
                "coalesce(?->>'displayName','') || ' ' || coalesce(?->>'handle','')",
                r.payload,
                r.payload
              ),
              ^q
            )
      )

    result = page(query, params)
    %{result | items: Enum.map(result.items, &actor/1)}
  end

  def search(params) do
    q = search_pattern(params["q"] || "")

    posts =
      page(
        from(r in PublicReadItem,
          where:
            r.entity_type in ^@top and
              ilike(
                fragment(
                  "coalesce(?->>'body','') || ' ' || coalesce(?->>'content','') || ' ' || coalesce(?->>'title','')",
                  r.payload,
                  r.payload,
                  r.payload
                ),
                ^q
              )
        ),
        params
      )

    %{
      actors: actors(params).items,
      posts: posts.items,
      next_cursor: posts.next_cursor,
      has_more: posts.has_more
    }
  end

  defp aliases(dids) do
    migrations =
      Repo.all(
        from(m in AnsibleRelay.Db.DidElixMigration,
          where: m.state == "completed" and (m.v1_did in ^dids or m.legacy_did in ^dids),
          select: {m.legacy_did, m.v1_did}
        )
      )

    Enum.uniq(dids ++ Enum.flat_map(migrations, fn {a, b} -> [a, b] end))
  end

  def context_notes(id, params) do
    target_row =
      Repo.one(
        from(r in PublicReadItem,
          where: r.entity_id == ^id and r.entity_type in ^@top,
          order_by: [desc: r.log_id],
          limit: 1
        )
      )

    with row when not is_nil(row) <- target_row,
         true <- readable?(row),
         item when not is_nil(item) <- present(row) do
      hash =
        "sha256:" <>
          Base.encode16(:crypto.hash(:sha256, canonical_json(item.payload)), case: :lower)

      target = %{
        entity_type: item.entity_type,
        entity_id: id,
        op_id: item.op_id,
        content_hash: hash
      }

      notes =
        page(
          from(r in PublicReadItem,
            where:
              r.entity_type == "context_note" and
                fragment("?->>'targetEntityId'", r.payload) == ^id
          ),
          params
        ).items
        |> Enum.filter(
          &(&1.payload["targetOpId"] == item.op_id and &1.payload["targetContentHash"] == hash)
        )
        |> Enum.map(fn n ->
          %{
            note_id: n.entity_id,
            author_did: n.author_did,
            body: n.payload["body"],
            sources: n.payload["sources"],
            target_entity_type: item.entity_type,
            target_entity_id: id,
            target_op_id: item.op_id,
            target_content_hash: hash
          }
        end)

      %{target: target, notes: notes}
    else
      _ -> %{target: nil, notes: []}
    end
  end

  defp canonical_json(value) when is_map(value),
    do:
      "{" <>
        Enum.map_join(Enum.sort_by(value, &elem(&1, 0)), ",", fn {k, v} ->
          Jason.encode!(k) <> ":" <> canonical_json(v)
        end) <> "}"

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)

  defp search_pattern(q),
    do:
      "%" <>
        (q
         |> String.slice(0, 200)
         |> String.replace("\\", "\\\\")
         |> String.replace("%", "\\%")
         |> String.replace("_", "\\_")) <> "%"

  # Cursor follows scanned rows, not filtered output: an inaccessible row cannot
  # stall pagination and filtering can never expose a protected record.
  defp page(query, params, direct \\ false) do
    limit = integer(params["limit"], 50) |> max(1) |> min(200)
    cursor = integer(params["cursor"], 0)
    query = from(r in query, where: r.op_type != "delete")
    query = if cursor > 0, do: from(r in query, where: r.log_id < ^cursor), else: query
    rows = Repo.all(from(r in query, order_by: [desc: r.log_id], limit: ^(limit + 1)))
    scanned = Enum.take(rows, limit)

    items =
      scanned
      |> Enum.filter(&readable?(&1, direct))
      |> Enum.map(&present/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&decorate/1)

    %{
      items: items,
      next_cursor: if(scanned == [], do: nil, else: List.last(scanned).log_id),
      has_more: length(rows) > limit
    }
  end

  defp readable?(row, direct \\ false, depth \\ 0)
  defp readable?(_, _, depth) when depth > 3, do: false
  defp readable?(%{op_type: "delete"}, _, _), do: false

  defp readable?(row, direct, depth) do
    p = row.payload || %{}
    vis = p["visibility"]
    board_id = p["boardId"] || p["board_id"]
    parent = p["threadId"] || p["targetId"] || p["targetEntityId"]

    visibility_ok =
      vis == "public" or (direct and vis == "unlisted") or
        (is_nil(vis) and row.entity_type in ~w(thread post comment reaction profile))

    board_ok =
      if is_binary(board_id) and board_id != "" do
        case PostingGate.get_board(board_id) do
          %{
            content_visibility: "public",
            access_policy: %{"read" => %{"requirement" => "public"}}
          } ->
            true

          _ ->
            false
        end
      else
        row.entity_type != "thread"
      end

    parent_ok =
      if row.entity_type in ~w(comment reaction post context_note) do
        is_binary(parent) and parent != row.entity_id and
          Enum.any?(
            Repo.all(
              from(r in PublicReadItem,
                where:
                  r.entity_id == ^parent and r.entity_type in ~w(murmur note thread post comment)
              )
            ),
            fn target ->
              readable?(target, direct, depth + 1) and not is_nil(present(target))
            end
          )
      else
        row.entity_type in ~w(thread murmur note profile)
      end

    visibility_ok and board_ok and parent_ok and p["encrypted"] != true and
      not Map.has_key?(p, "ciphertext")
  end

  defp decorate(item) do
    # These are public presentation counts only. Never count protected replies
    # or turn a raw signed author DID into proof of an identity qualification.
    id = item.entity_id

    children =
      Repo.all(
        from(r in PublicReadItem,
          where:
            r.entity_type in ~w(post comment reaction) and
              (fragment("?->>'threadId'", r.payload) == ^id or
                 fragment("?->>'targetId'", r.payload) == ^id)
        )
      )
      |> Enum.filter(&readable?/1)
      |> Enum.map(&present/1)
      |> Enum.reject(&is_nil/1)

    thread =
      if is_binary(item.thread_id),
        do: Repo.get_by(PublicReadItem, entity_type: "thread", entity_id: item.thread_id)

    payload =
      if thread && readable?(thread) && present(thread),
        do: Map.put_new(item.payload, "threadTitle", thread.payload["title"]),
        else: item.payload

    Map.merge(item, %{
      payload: payload,
      comment_count: Enum.count(children, &(&1.entity_type in ~w(post comment))),
      reaction_count:
        Enum.count(
          children,
          &(&1.entity_type == "reaction" and &1.payload["reactionType"] == "like")
        ),
      repost_count:
        Enum.count(
          children,
          &(&1.entity_type == "reaction" and &1.payload["reactionType"] == "repost")
        )
    })
  end

  defp present(row) do
    original_author = OpStore.create_op_author(row.entity_type, row.entity_id)

    if is_binary(original_author) and MigrationStore.equivalent?(original_author, row.author_did) do
      op = %{
        log_id: row.log_id,
        op_id: row.op_id,
        author_did: row.author_did,
        entity_type: row.entity_type,
        entity_id: row.entity_id,
        op_type: row.op_type,
        payload: row.signed_payload,
        signature: row.signature,
        schema_version: row.schema_version,
        received_at: row.received_at && DateTime.to_iso8601(row.received_at)
      }

      [overlaid] = Moderation.overlay_ops([op])

      if not Map.get(overlaid, :removed, false) do
        evidence = OpsController.public_evidence(op)

        if valid_authority?(evidence) do
          p = row.payload
          board = PostingGate.get_board(p["boardId"] || p["board_id"])

          Map.merge(evidence, %{
            signed_payload: row.signed_payload,
            payload: p,
            sig_verified: true,
            board_id: board && to_string(board.board_id),
            thread_id:
              p["threadId"] || p["thread_id"] ||
                if(row.entity_type == "thread", do: row.entity_id),
            visibility: p["visibility"] || "public",
            created_at: p["publishedAt"] || p["createdAt"],
            locked: Map.get(overlaid, :locked, false),
            lock_reason_code: Map.get(overlaid, :lock_reason_code)
          })
        end
      end
    end
  end

  defp valid_authority?(evidence) do
    status = evidence.authority_status
    credential = status.credential

    status.state == "active" and not status.superseded and
      (is_nil(credential) or credential.state == "active" or
         (credential.state == "revoked" and is_binary(credential.revoked_at) and
            is_binary(evidence.received_at) and evidence.received_at < credential.revoked_at))
  end

  defp actor(item) do
    p = item.payload

    %{
      did: item.canonical_author_did,
      display_name: p["displayName"],
      handle: p["handle"],
      bio: p["bio"],
      avatar_url: p["avatarUrl"],
      reputation_tier: item.reputation_tier,
      public_credentials:
        AnsibleRelay.Identity.PublicProfileCredentialStore.list_public(
          item.author_did,
          Enum.filter(List.wrap(p["credentialTypes"]), &is_binary/1)
        ),
      reason: "recent_public_profile"
    }
  end

  defp integer(v, _) when is_integer(v), do: v

  defp integer(v, fallback) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> fallback
    end
  end

  defp integer(_, fallback), do: fallback
end
