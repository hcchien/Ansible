defmodule AnsibleRelay.ForumHost.Store do
  @moduledoc "Durable co-located Forum Host storage and metadata helpers."

  import Ecto.Query

  alias AnsibleRelay.Repo
  alias AnsibleRelay.Db.{ForumHostAcceptedIntent, ForumHostAnnouncement, ForumHostBoard}

  @default_base_url "http://localhost:4001"
  @max_slug_attempts 20

  def ensure_seeded! do
    Enum.each(seed_boards(), &upsert_seed_board/1)
    Enum.each(seed_announcements(), &upsert_seed_announcement/1)
    :ok
  end

  def host_info do
    %{
      forum_host_id: forum_host_id(),
      display_name: display_name(),
      canonical_base_url: base_url(),
      base_url: base_url(),
      canonical_host_uri: base_url(),
      server_kind: "ansibleForumHost",
      constitution_compliance: constitution_compliance(),
      host_public_keys: host_public_keys(),
      accepted_session_issuers: accepted_session_issuers(),
      rules: rules(),
      moderation_policy: moderation_policy(),
      posting_policy: posting_policy(),
      capabilities: %{
        create_boards: true,
        create_threads: true,
        cross_post: true,
        announcements: true
      }
    }
  end

  def list_boards do
    ensure_seeded!()

    ForumHostBoard
    |> order_by([board], asc: board.title)
    |> Repo.all()
  end

  @doc """
  Boards created by `did`, derived from the accepted create_board intents
  (subscriptions are client-local, but board authorship is recorded host-side).
  Lets a freshly-installed client re-list the boards it created without a
  manual re-subscribe. Same serialized shape as `list_boards/0`.
  """
  def list_boards_created_by(did) when is_binary(did) do
    ensure_seeded!()

    created_ids =
      from(i in ForumHostAcceptedIntent,
        where:
          i.author_did == ^did and i.action == "create_board" and
            i.result_kind == "forum_host_board",
        select: i.result_id
      )
      |> Repo.all()

    if created_ids == [] do
      []
    else
      ForumHostBoard
      |> where([board], board.hosted_board_id in ^created_ids)
      |> order_by([board], asc: board.title)
      |> Repo.all()
    end
  end

  def list_boards_created_by(_did), do: []

  @doc """
  Searches boards by title/description/tag substring (case-insensitive). Boards
  are host-owned, so board discovery lives here rather than in the AppView. An
  empty query falls back to the full ordered list (browse).
  """
  def search_boards(query, limit \\ 20) do
    ensure_seeded!()
    q = String.trim(query || "")
    limit = limit |> min(50) |> max(1)

    if q == "" do
      ForumHostBoard |> order_by([b], asc: b.title) |> limit(^limit) |> Repo.all()
    else
      like = "%" <> escape_like(q) <> "%"

      ForumHostBoard
      |> where(
        [b],
        ilike(b.title, ^like) or ilike(b.description, ^like) or
          fragment("EXISTS (SELECT 1 FROM unnest(?) AS t WHERE t ILIKE ?)", b.tags, ^like)
      )
      |> order_by([b], asc: b.title)
      |> limit(^limit)
      |> Repo.all()
    end
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def list_announcements(owner_kind \\ nil) do
    ensure_seeded!()
    now = DateTime.utc_now()

    ForumHostAnnouncement
    |> where([announcement], is_nil(announcement.starts_at) or announcement.starts_at <= ^now)
    |> where([announcement], is_nil(announcement.expires_at) or announcement.expires_at > ^now)
    |> maybe_owner(owner_kind)
    |> order_by([announcement], asc: announcement.inserted_at)
    |> Repo.all()
  end

  def create_board(attrs) do
    with {:ok, request} <- normalize_create_board_attrs(attrs) do
      payload_hash = payload_hash(request)
      create_board_with_slug(request, payload_hash, 1)
    end
  end

  def forum_host_id do
    Application.get_env(:ansible_relay, :forum_host_id, "host-local-dev")
  end

  def base_url do
    Application.get_env(:ansible_relay, :forum_host_base_url, @default_base_url)
  end

  defp upsert_seed_board(attrs) do
    slug = Map.fetch!(attrs, "slug")
    hosted_board_id = Map.get(attrs, "hosted_board_id", slug)

    changes =
      attrs
      |> Map.put("hosted_board_id", hosted_board_id)
      |> Map.put(
        "canonical_board_uri",
        Map.get(attrs, "canonical_board_uri", "#{base_url()}/boards/#{slug}")
      )

    %ForumHostBoard{}
    |> ForumHostBoard.changeset(changes)
    |> Repo.insert!(
      on_conflict:
        {:replace,
         [
           :slug,
           :canonical_board_uri,
           :title,
           :description,
           :language,
           :tags,
           :permissions,
           :posting_policy,
           :moderation_policy,
           :updated_at
         ]},
      conflict_target: :hosted_board_id
    )
  end

  defp upsert_seed_announcement(attrs) do
    %ForumHostAnnouncement{}
    |> ForumHostAnnouncement.changeset(attrs)
    |> Repo.insert!(
      on_conflict:
        {:replace,
         [
           :owner_kind,
           :hosted_board_id,
           :title,
           :body,
           :severity,
           :locale,
           :url,
           :starts_at,
           :expires_at,
           :updated_at
         ]},
      conflict_target: :announcement_id
    )
  end

  defp maybe_owner(query, nil), do: query

  defp maybe_owner(query, owner_kind) do
    where(query, [announcement], announcement.owner_kind == ^owner_kind)
  end

  defp seed_boards do
    Application.get_env(:ansible_relay, :forum_host_seed_boards, [
      %{
        "hosted_board_id" => "general",
        "slug" => "general",
        "title" => "General",
        "description" => "General discussion",
        "language" => "en",
        "tags" => ["starter"],
        "permissions" => %{"read" => true, "write" => true},
        "posting_policy" => posting_policy(),
        "moderation_policy" => moderation_policy()
      }
    ])
  end

  defp seed_announcements do
    Application.get_env(:ansible_relay, :forum_host_announcements, [])
  end

  defp display_name do
    Application.get_env(:ansible_relay, :forum_host_display_name, "Local Forum Host")
  end

  defp constitution_compliance do
    Application.get_env(:ansible_relay, :forum_host_constitution_compliance, "unknown")
  end

  defp host_public_keys do
    Application.get_env(:ansible_relay, :forum_host_public_keys, [])
  end

  defp accepted_session_issuers do
    Application.get_env(:ansible_relay, :forum_host_accepted_session_issuers, [
      %{"issuer" => Application.get_env(:ansible_relay, :relay_origin, base_url())}
    ])
  end

  defp rules do
    Application.get_env(:ansible_relay, :forum_host_rules, %{
      "summary" => "Be relevant, lawful, and respectful of board rules."
    })
  end

  defp posting_policy do
    Application.get_env(:ansible_relay, :forum_host_posting_policy, %{
      "min_trust_tier" => "self_custody_did"
    })
  end

  defp moderation_policy do
    Application.get_env(:ansible_relay, :forum_host_moderation_policy, %{
      "reason_codes" => ["spam", "abuse", "illegal", "off_topic"],
      "appeals" => true
    })
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "board"
      slug -> slug
    end
  end

  defp create_board_with_slug(request, payload_hash, attempt)
       when attempt <= @max_slug_attempts do
    slug = slug_candidate(request.base_slug, attempt)
    board_attrs = board_attrs(request.stored_board_payload, slug)
    accepted_intent_attrs = accepted_intent_attrs(request, payload_hash, slug)

    Repo.transaction(fn ->
      case insert_accepted_intent(accepted_intent_attrs) do
        :inserted ->
          insert_board_or_rollback(board_attrs)

        :conflict ->
          resolve_accepted_intent(request.intent_id, payload_hash)

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
    |> case do
      {:ok, result} ->
        result

      {:error, {:slug_conflict, _changeset}} ->
        create_board_with_slug(request, payload_hash, attempt + 1)

      {:error, {:error, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_board_with_slug(%{base_slug: base_slug}, _payload_hash, _attempt) do
    {:error, {:slug_unavailable, base_slug}}
  end

  defp slug_candidate(base_slug, 1), do: base_slug
  defp slug_candidate(base_slug, attempt), do: "#{base_slug}-#{attempt}"

  defp insert_accepted_intent(attrs) do
    now = DateTime.utc_now()
    attrs = Map.put(attrs, :accepted_at, now)
    changeset = ForumHostAcceptedIntent.changeset(%ForumHostAcceptedIntent{}, attrs)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, intent} ->
        row = %{
          intent_id: intent.intent_id,
          author_did: intent.author_did,
          action: intent.action,
          payload_hash: intent.payload_hash,
          result_kind: intent.result_kind,
          result_id: intent.result_id,
          accepted_at: intent.accepted_at,
          inserted_at: now,
          updated_at: now
        }

        case Repo.insert_all(ForumHostAcceptedIntent, [row],
               on_conflict: :nothing,
               conflict_target: [:intent_id]
             ) do
          {1, _rows} -> :inserted
          {0, _rows} -> :conflict
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp insert_board_or_rollback(attrs) do
    %ForumHostBoard{}
    |> ForumHostBoard.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, board} ->
        {:ok, board}

      {:error, changeset} ->
        if slug_conflict?(changeset) do
          Repo.rollback({:slug_conflict, changeset})
        else
          Repo.rollback({:error, changeset})
        end
    end
  end

  defp slug_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {:hosted_board_id, {_message, opts}} -> opts[:constraint] == :unique
      {:slug, {_message, opts}} -> opts[:constraint] == :unique
      {:canonical_board_uri, {_message, opts}} -> opts[:constraint] == :unique
      _error -> false
    end)
  end

  defp resolve_accepted_intent(intent_id, payload_hash) do
    case Repo.get(ForumHostAcceptedIntent, intent_id) do
      %ForumHostAcceptedIntent{payload_hash: ^payload_hash, result_id: result_id} ->
        {:ok, Repo.get!(ForumHostBoard, result_id)}

      %ForumHostAcceptedIntent{} ->
        {:error, :duplicate_intent}

      nil ->
        {:error, :duplicate_intent}
    end
  end

  defp payload_hash(request) do
    %{
      action: "create_board",
      intent_id: request.intent_id,
      author_did: request.author_did,
      board: request.submitted_board_payload
    }
    |> canonical_payload()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp accepted_intent_attrs(request, payload_hash, hosted_board_id) do
    %{
      intent_id: request.intent_id,
      author_did: request.author_did,
      action: "create_board",
      payload_hash: payload_hash,
      result_kind: "forum_host_board",
      result_id: hosted_board_id
    }
  end

  defp board_attrs(stored_board_payload, slug) do
    Map.merge(stored_board_payload, %{
      hosted_board_id: slug,
      slug: slug,
      canonical_board_uri: "#{base_url()}/boards/#{slug}"
    })
  end

  defp normalize_create_board_attrs(attrs) do
    missing = missing_create_board_fields(attrs)

    cond do
      missing != [] ->
        {:error, {:invalid_board, missing}}

      not valid_posting_policy?(get_attr(attrs, :posting_policy)) ->
        {:error, :invalid_min_post_tier}

      external_inclusion_conflicts_with_trust_gate?(get_attr(attrs, :posting_policy)) ->
        {:error, :external_inclusion_conflicts_with_trust_gate}

      true ->
        title = get_attr(attrs, :title)

        {:ok,
         %{
           intent_id: get_attr(attrs, :intent_id),
           author_did: get_attr(attrs, :author_did),
           base_slug: slugify(title),
           submitted_board_payload: submitted_board_payload(attrs),
           stored_board_payload: stored_board_payload(attrs)
         }}
    end
  end

  # posting_policy["min_post_tier"] is optional (absent = ungated) but must be
  # a known tier when present.
  defp valid_posting_policy?(%{} = policy) do
    case Map.get(policy, "min_post_tier") || Map.get(policy, :min_post_tier) do
      nil -> true
      tier -> AnsibleRelay.ReputationTier.valid_min_post_tier?(tier)
    end
  end

  defp valid_posting_policy?(_policy), do: true

  # Constitution invariant: reject a board that is BOTH externally inclusive
  # (`external_inclusion == true`) AND trust-gated to a real-human tier
  # (`min_post_tier` above `basic`, e.g. `verified_human`). A 真人版 board
  # cannot carry unverified external content. `external_inclusion` defaults
  # false and is reversible (a host can turn it off later).
  defp external_inclusion_conflicts_with_trust_gate?(%{} = policy) do
    external_inclusion?(policy) and gated_min_post_tier?(policy)
  end

  defp external_inclusion_conflicts_with_trust_gate?(_policy), do: false

  defp external_inclusion?(%{} = policy) do
    case Map.get(policy, "external_inclusion") || Map.get(policy, :external_inclusion) do
      true -> true
      _value -> false
    end
  end

  defp gated_min_post_tier?(%{} = policy) do
    case Map.get(policy, "min_post_tier") || Map.get(policy, :min_post_tier) do
      tier when is_binary(tier) ->
        AnsibleRelay.ReputationTier.valid_min_post_tier?(tier) and tier != "basic"

      _value ->
        false
    end
  end

  defp missing_create_board_fields(attrs) do
    [:intent_id, :author_did, :title]
    |> Enum.reject(fn field ->
      case get_attr(attrs, field, :missing) do
        value when is_binary(value) -> String.trim(value) != ""
        _value -> false
      end
    end)
  end

  defp submitted_board_payload(attrs) do
    Enum.reduce(
      [:description, :language, :tags, :permissions, :posting_policy, :moderation_policy],
      %{title: get_attr(attrs, :title)},
      fn field, payload ->
        if has_attr?(attrs, field) do
          Map.put(payload, field, get_attr(attrs, field))
        else
          payload
        end
      end
    )
  end

  defp stored_board_payload(attrs) do
    %{
      title: get_attr(attrs, :title),
      description: get_attr(attrs, :description),
      language: get_attr(attrs, :language),
      tags: get_attr(attrs, :tags, []),
      permissions: get_attr(attrs, :permissions, %{"read" => true, "write" => true}),
      posting_policy: get_attr(attrs, :posting_policy, posting_policy()),
      moderation_policy: get_attr(attrs, :moderation_policy, moderation_policy())
    }
  end

  defp has_attr?(attrs, field) do
    Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field))
  end

  defp get_attr(attrs, field, default \\ nil) do
    cond do
      Map.has_key?(attrs, field) -> Map.get(attrs, field)
      Map.has_key?(attrs, Atom.to_string(field)) -> Map.get(attrs, Atom.to_string(field))
      true -> default
    end
  end

  defp canonical_payload(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      {to_string(key), canonical_payload(nested_value)}
    end)
    |> Enum.sort_by(fn {key, _nested_value} -> key end)
    |> Enum.map(fn {key, nested_value} -> [key, nested_value] end)
  end

  defp canonical_payload(value) when is_list(value) do
    Enum.map(value, &canonical_payload/1)
  end

  defp canonical_payload(value), do: value
end
