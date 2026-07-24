defmodule AnsibleRelay.ForumHost.Store do
  @moduledoc "Durable co-located Forum Host storage and metadata helpers."

  import Ecto.Query

  alias AnsibleRelay.Repo
  alias AnsibleRelay.ForumHost.ReceiptSigner

  alias AnsibleRelay.Db.{
    ForumHostAcceptedIntent,
    ForumHostAnnouncement,
    ForumHostBoard,
    ForumHostBoardPolicyVersion
  }

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

  def list_public_boards do
    ensure_seeded!()

    ForumHostBoard
    |> where(
      [board],
      board.content_visibility == "public" and
        fragment("?->>'discovery' = 'public'", board.access_policy)
    )
    |> order_by([board], asc: board.title)
    |> Repo.all()
  end

  def protected_boards_exist? do
    ForumHostBoard
    |> where(
      [board],
      board.content_visibility != "public" or
        fragment("?->'read'->>'requirement' != 'public'", board.access_policy)
    )
    |> Repo.exists?()
  end

  def list_board_policy_versions(board_id) when is_binary(board_id) do
    ForumHostBoardPolicyVersion
    |> where([version], version.hosted_board_id == ^board_id)
    |> order_by([version], desc: version.version)
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
      |> where(
        [board],
        board.content_visibility == "public" and
          fragment("?->>'discovery' = 'public'", board.access_policy)
      )
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
      ForumHostBoard
      |> where(
        [b],
        b.content_visibility == "public" and
          fragment("?->>'discovery' = 'public'", b.access_policy)
      )
      |> order_by([b], asc: b.title)
      |> limit(^limit)
      |> Repo.all()
    else
      like = "%" <> escape_like(q) <> "%"

      ForumHostBoard
      |> where(
        [b],
        b.content_visibility == "public" and
          fragment("?->>'discovery' = 'public'", b.access_policy)
      )
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

  @doc """
  Applies a verified `update_board` intent. Only the board's creator (the
  author DID of the accepted `create_board` intent that produced the board)
  may update it; seed/config boards have no creator record, so nobody can
  update them through this path (fail closed). Replays are idempotent: an
  identical accepted intent returns the current board, a same-id intent with
  different content is rejected as `duplicate_intent`. The board's identity
  (hosted_board_id, slug, canonical URI) never changes on update.
  """
  def update_board(attrs) do
    with {:ok, request} <- normalize_update_board_attrs(attrs) do
      payload_hash = update_board_payload_hash(request)

      Repo.transaction(fn ->
        case fetch_board_for_creator(request.board_id, request.author_did) do
          {:ok, board} ->
            case insert_accepted_intent(update_board_intent_attrs(request, payload_hash)) do
              :inserted ->
                update_board_or_rollback(board, request)

              :conflict ->
                resolve_accepted_update_intent(request.intent_id, payload_hash, request.board_id)

              {:error, changeset} ->
                Repo.rollback({:error, changeset})
            end

          {:error, reason} ->
            Repo.rollback({:error, reason})
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, {:error, reason}} -> {:error, reason}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Applies or schedules an independently governed board access policy update."
  def update_board_policy(attrs) do
    with {:ok, request} <- normalize_board_policy_attrs(attrs) do
      payload_hash = board_policy_payload_hash(request)

      Repo.transaction(fn ->
        case fetch_board_for_creator(request.board_id, request.author_did) do
          {:ok, board} ->
            case insert_accepted_intent(board_policy_intent_attrs(request, payload_hash)) do
              :inserted ->
                with :ok <- require_no_pending_policy(board),
                     :ok <- require_previous_policy_hash(board, request.previous_policy_hash),
                     :ok <- verify_policy_approvals(board, request),
                     :ok <- require_sensitive_delay(board, request),
                     {:ok, result} <- persist_board_policy_update(board, request) do
                  result
                else
                  {:error, reason} -> Repo.rollback({:error, reason})
                end

              :conflict ->
                case resolve_accepted_policy_intent(
                       request.intent_id,
                       payload_hash,
                       request.board_id
                     ) do
                  {:ok, result} -> result
                  {:error, reason} -> Repo.rollback({:error, reason})
                end

              {:error, changeset} ->
                Repo.rollback({:error, changeset})
            end

          {:error, reason} ->
            Repo.rollback({:error, reason})
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, {:error, reason}} -> {:error, reason}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def activate_due_board_policy(%ForumHostBoard{} = board) do
    now = DateTime.utc_now()

    case from(version in ForumHostBoardPolicyVersion,
           where:
             version.hosted_board_id == ^board.hosted_board_id and
               version.version == ^(board.access_policy_version + 1) and
               version.effective_at <= ^now and is_nil(version.superseded_at),
           limit: 1
         )
         |> Repo.one() do
      nil ->
        board

      version ->
        Repo.transaction(fn ->
          case activate_policy_version(board, version.version, version.canonical_policy, now) do
            {:ok, updated} -> updated
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, updated} -> updated
          _ -> board
        end
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

    board =
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

    ensure_canonical_board_uri!(board)
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
    configured = Application.get_env(:ansible_relay, :forum_host_public_keys, [])

    case ReceiptSigner.public_key() do
      {:ok, receipt_key} ->
        [receipt_key | Enum.reject(configured, &(&1["key_id"] == receipt_key["key_id"]))]

      {:error, _reason} ->
        configured
    end
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
          with {:ok, board} <- insert_board_or_rollback(board_attrs),
               :ok <- insert_policy_version(board, request.author_did, %{}) do
            {:ok, board}
          end

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
        {:ok, ensure_canonical_board_uri!(board)}

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

  defp ensure_canonical_board_uri!(%ForumHostBoard{board_id: board_id} = board)
       when is_integer(board_id) do
    canonical_board_uri = "#{base_url()}/boards/#{board_id}"

    if board.canonical_board_uri == canonical_board_uri do
      board
    else
      board
      |> Ecto.Changeset.change(canonical_board_uri: canonical_board_uri)
      |> Repo.update!()
    end
  end

  defp fetch_board_for_creator(board_id, author_did) do
    case Repo.get(ForumHostBoard, board_id) do
      nil ->
        {:error, :board_not_found}

      board ->
        creator = board_creator(board_id)

        if is_binary(creator) and creator == author_did do
          {:ok, board}
        else
          {:error, :not_board_creator}
        end
    end
  end

  # created_by is derived from the accepted create_board intent that produced
  # the board — the same record `list_boards_created_by/1` relies on.
  defp board_creator(board_id) do
    from(i in ForumHostAcceptedIntent,
      where:
        i.action == "create_board" and i.result_kind == "forum_host_board" and
          i.result_id == ^board_id,
      select: i.author_did,
      limit: 1
    )
    |> Repo.one()
  end

  defp update_board_or_rollback(board, request) do
    with :ok <- require_expected_policy_version(board, request),
         changes <- apply_policy_version(board, request.changes),
         {:ok, updated} <- board |> ForumHostBoard.changeset(changes) |> Repo.update(),
         :ok <- maybe_record_policy_version(board, updated, request) do
      {:ok, updated}
    else
      {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback({:error, changeset})
      {:error, reason} -> Repo.rollback({:error, reason})
    end
  end

  defp require_expected_policy_version(board, %{policy_update?: true} = request) do
    if request.expected_policy_version == board.access_policy_version,
      do: :ok,
      else: {:error, :policy_version_conflict}
  end

  defp require_expected_policy_version(_board, _request), do: :ok

  defp apply_policy_version(board, changes) do
    policy_changed? =
      Enum.any?(
        [:access_policy, :content_visibility, :federation_policy],
        &Map.has_key?(changes, &1)
      )

    changes =
      if policy_changed?,
        do: Map.put(changes, :access_policy_version, board.access_policy_version + 1),
        else: changes

    next_visibility = Map.get(changes, :content_visibility, board.content_visibility)

    cond do
      next_visibility != "end_to_end_encrypted" ->
        Map.put(changes, :encryption_state, "disabled")

      board.content_visibility != "end_to_end_encrypted" or policy_changed? ->
        Map.put(changes, :encryption_state, "rotation_required")

      true ->
        changes
    end
  end

  defp maybe_record_policy_version(_previous, _updated, %{policy_update?: false}), do: :ok

  defp maybe_record_policy_version(previous, updated, request) do
    now = DateTime.utc_now()

    from(version in ForumHostBoardPolicyVersion,
      where:
        version.hosted_board_id == ^previous.hosted_board_id and
          is_nil(version.superseded_at)
    )
    |> Repo.update_all(set: [superseded_at: now])

    insert_policy_version(updated, request.author_did, request.approvals, now)
  end

  defp insert_policy_version(board, actor_did, approvals, now \\ DateTime.utc_now()) do
    canonical_policy = %{
      "access_policy" => board.access_policy,
      "content_visibility" => board.content_visibility,
      "federation_policy" => board.federation_policy
    }

    policy_hash =
      canonical_policy
      |> canonical_payload()
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %ForumHostBoardPolicyVersion{}
    |> ForumHostBoardPolicyVersion.changeset(%{
      policy_hash: policy_hash,
      hosted_board_id: board.hosted_board_id,
      version: board.access_policy_version,
      canonical_policy: canonical_policy,
      actor_did: actor_did,
      approvals: approvals,
      effective_at: now
    })
    |> Repo.insert()
    |> case do
      {:ok, _version} -> :ok
      {:error, changeset} -> Repo.rollback({:error, changeset})
    end
  end

  defp resolve_accepted_update_intent(intent_id, payload_hash, board_id) do
    case Repo.get(ForumHostAcceptedIntent, intent_id) do
      %ForumHostAcceptedIntent{payload_hash: ^payload_hash, result_id: ^board_id} ->
        {:ok, Repo.get!(ForumHostBoard, board_id)}

      _other ->
        {:error, :duplicate_intent}
    end
  end

  defp update_board_payload_hash(request) do
    %{
      action: "update_board",
      intent_id: request.intent_id,
      author_did: request.author_did,
      board_id: request.board_id,
      board: request.changes,
      expected_policy_version: request.expected_policy_version,
      approvals: request.approvals
    }
    |> canonical_payload()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp update_board_intent_attrs(request, payload_hash) do
    %{
      intent_id: request.intent_id,
      author_did: request.author_did,
      action: "update_board",
      payload_hash: payload_hash,
      result_kind: "forum_host_board",
      result_id: request.board_id
    }
  end

  defp normalize_update_board_attrs(attrs) do
    missing = missing_update_board_fields(attrs)
    changes = update_board_changes(attrs)

    cond do
      missing != [] ->
        {:error, {:invalid_board, missing}}

      changes == %{} ->
        {:error, :invalid_board}

      Map.has_key?(changes, :title) and not non_empty_string?(changes[:title]) ->
        {:error, :invalid_board}

      Map.has_key?(changes, :posting_policy) and
          not valid_posting_policy?(changes[:posting_policy]) ->
        {:error, :invalid_min_post_tier}

      Map.has_key?(changes, :posting_policy) and
          external_inclusion_conflicts_with_trust_gate?(changes[:posting_policy]) ->
        {:error, :external_inclusion_conflicts_with_trust_gate}

      Map.has_key?(changes, :access_policy) and
          AnsibleRelay.ForumHost.BoardAccessPolicy.validate(changes[:access_policy]) != :ok ->
        {:error, :invalid_access_policy}

      true ->
        policy_update? =
          Enum.any?(
            [:access_policy, :content_visibility, :federation_policy],
            &Map.has_key?(changes, &1)
          )

        {:ok,
         %{
           intent_id: get_attr(attrs, :intent_id),
           author_did: get_attr(attrs, :author_did),
           board_id: get_attr(attrs, :board_id),
           changes: changes,
           policy_update?: policy_update?,
           expected_policy_version: get_attr(attrs, :expected_policy_version),
           approvals: get_attr(attrs, :approvals, %{})
         }}
    end
  end

  defp update_board_changes(attrs) do
    Enum.reduce(
      [
        :title,
        :description,
        :posting_policy
      ],
      %{},
      fn field, changes ->
        if has_attr?(attrs, field) do
          Map.put(changes, field, get_attr(attrs, field))
        else
          changes
        end
      end
    )
  end

  defp normalize_board_policy_attrs(attrs) do
    policy = get_attr(attrs, :new_policy)
    approvals = get_attr(attrs, :approvals, %{})

    with true <- is_map(policy),
         true <- is_map(approvals),
         access when is_map(access) <- get_attr(policy, :access_policy),
         :ok <- AnsibleRelay.ForumHost.BoardAccessPolicy.validate(access),
         visibility when visibility in ["public", "host_visible", "end_to_end_encrypted"] <-
           get_attr(policy, :content_visibility),
         federation when is_map(federation) <- get_attr(policy, :federation_policy),
         true <- get_attr(access, :content_visibility) == visibility,
         true <- get_attr(access, :federation) == get_attr(federation, :mode),
         {:ok, effective_at, _} <- DateTime.from_iso8601(get_attr(attrs, :effective_at, "")) do
      {:ok,
       %{
         intent_id: get_attr(attrs, :intent_id),
         author_did: get_attr(attrs, :author_did),
         board_id: get_attr(attrs, :board_id),
         previous_policy_hash: get_attr(attrs, :previous_policy_hash),
         access_policy: access,
         content_visibility: visibility,
         federation_policy: federation,
         effective_at: effective_at,
         approvals: approvals
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_access_policy}
    end
  end

  defp require_previous_policy_hash(board, expected) do
    if board_policy_hash(board) == expected,
      do: :ok,
      else: {:error, :policy_hash_conflict}
  end

  defp require_no_pending_policy(board) do
    pending? =
      from(version in ForumHostBoardPolicyVersion,
        where:
          version.hosted_board_id == ^board.hosted_board_id and
            version.version > ^board.access_policy_version and
            is_nil(version.superseded_at)
      )
      |> Repo.exists?()

    if pending?, do: {:error, :policy_change_pending}, else: :ok
  end

  defp verify_policy_approvals(board, request) do
    creator = board_creator(board.hosted_board_id)
    governance = get_attr(board.moderation_policy || %{}, :governance, %{})
    admins = get_attr(governance, :administrators, [creator])
    threshold = get_attr(governance, :threshold, 1)

    valid_governance? =
      is_list(admins) and admins != [] and Enum.all?(admins, &non_empty_string?/1) and
        is_integer(threshold) and threshold in 1..length(admins) and creator in admins

    approval_payload =
      %{
        "type" => "io.trisaura.forum.boardPolicyApproval",
        "version" => 1,
        "board_id" => request.board_id,
        "previous_policy_hash" => request.previous_policy_hash,
        "new_policy" => %{
          "access_policy" => request.access_policy,
          "content_visibility" => request.content_visibility,
          "federation_policy" => request.federation_policy
        },
        "effective_at" => DateTime.to_iso8601(request.effective_at)
      }
      |> canonical_payload()
      |> Jason.encode!()

    additional =
      request.approvals
      |> Enum.count(fn {did, signature} ->
        did in admins and did != request.author_did and is_binary(signature) and
          AnsibleRelay.IdentityCache.verify_signature(did, approval_payload, signature)
      end)

    cond do
      not valid_governance? -> {:error, :invalid_board_governance}
      request.author_did not in admins -> {:error, :not_board_governor}
      1 + additional < threshold -> {:error, :policy_approval_threshold_not_met}
      true -> :ok
    end
  end

  defp require_sensitive_delay(board, request) do
    minimum = DateTime.add(DateTime.utc_now(), 86_400, :second)

    if sensitive_policy_change?(board, request) and
         DateTime.compare(request.effective_at, minimum) == :lt do
      {:error, :sensitive_policy_delay_required}
    else
      :ok
    end
  end

  defp sensitive_policy_change?(board, request) do
    old = board.access_policy || %{}
    new = request.access_policy
    old_issuers = policy_issuers(old)
    new_issuers = policy_issuers(new)

    not MapSet.subset?(new_issuers, old_issuers) or
      (protected_requirement?(get_attr(old, :read)) and
         not protected_requirement?(get_attr(new, :read))) or
      (board.content_visibility != "public" and request.content_visibility == "public") or
      (get_attr(board.federation_policy || %{}, :mode) == "disabled" and
         get_attr(request.federation_policy, :mode) == "enabled")
  end

  defp protected_requirement?(action) when is_map(action) do
    get_attr(action, :requirement) not in ["public", "posting_policy"]
  end

  defp protected_requirement?(_), do: false

  defp policy_issuers(policy) do
    policy
    |> get_attr(:requirements, %{})
    |> Map.values()
    |> Enum.flat_map(&get_attr(&1, :trusted_issuers, []))
    |> MapSet.new()
  end

  defp persist_board_policy_update(board, request) do
    next_version = board.access_policy_version + 1
    now = DateTime.utc_now()
    future? = DateTime.compare(request.effective_at, now) == :gt

    policy = %{
      "access_policy" => request.access_policy,
      "content_visibility" => request.content_visibility,
      "federation_policy" => request.federation_policy
    }

    with {:ok, _} <-
           %ForumHostBoardPolicyVersion{}
           |> ForumHostBoardPolicyVersion.changeset(%{
             policy_hash: policy_hash(policy),
             hosted_board_id: board.hosted_board_id,
             version: next_version,
             canonical_policy: policy,
             actor_did: request.author_did,
             approvals: request.approvals,
             effective_at: request.effective_at
           })
           |> Repo.insert() do
      if future? do
        {:ok, board}
      else
        activate_policy_version(board, next_version, policy, now)
      end
    end
  end

  defp board_policy_payload_hash(request) do
    %{
      action: "update_board_policy",
      intent_id: request.intent_id,
      author_did: request.author_did,
      board_id: request.board_id,
      previous_policy_hash: request.previous_policy_hash,
      new_policy: %{
        access_policy: request.access_policy,
        content_visibility: request.content_visibility,
        federation_policy: request.federation_policy
      },
      effective_at: DateTime.to_iso8601(request.effective_at),
      approvals: request.approvals
    }
    |> canonical_payload()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp board_policy_intent_attrs(request, payload_hash) do
    %{
      intent_id: request.intent_id,
      author_did: request.author_did,
      action: "update_board_policy",
      payload_hash: payload_hash,
      result_kind: "forum_host_board_policy",
      result_id: request.board_id
    }
  end

  defp resolve_accepted_policy_intent(intent_id, payload_hash, board_id) do
    case Repo.get(ForumHostAcceptedIntent, intent_id) do
      %ForumHostAcceptedIntent{
        payload_hash: ^payload_hash,
        result_kind: "forum_host_board_policy",
        result_id: ^board_id
      } ->
        {:ok, Repo.get!(ForumHostBoard, board_id)}

      _other ->
        {:error, :duplicate_intent}
    end
  end

  defp activate_policy_version(board, version, policy, now) do
    changes = %{
      access_policy: policy["access_policy"],
      access_policy_version: version,
      content_visibility: policy["content_visibility"],
      federation_policy: policy["federation_policy"]
    }

    with {:ok, updated} <-
           board
           |> ForumHostBoard.changeset(apply_policy_version(board, changes))
           |> Repo.update() do
      from(previous in ForumHostBoardPolicyVersion,
        where:
          previous.hosted_board_id == ^board.hosted_board_id and previous.version < ^version and
            is_nil(previous.superseded_at)
      )
      |> Repo.update_all(set: [superseded_at: now])

      {:ok, updated}
    end
  end

  defp board_policy_hash(board) do
    policy_hash(%{
      "access_policy" => board.access_policy,
      "content_visibility" => board.content_visibility,
      "federation_policy" => board.federation_policy
    })
  end

  defp policy_hash(policy) do
    policy
    |> canonical_payload()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp missing_update_board_fields(attrs) do
    [:intent_id, :author_did, :board_id]
    |> Enum.reject(fn field -> non_empty_string?(get_attr(attrs, field, :missing)) end)
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

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
      [
        :description,
        :language,
        :tags,
        :permissions,
        :posting_policy,
        :moderation_policy,
        :access_policy,
        :content_visibility,
        :federation_policy
      ],
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
      moderation_policy: get_attr(attrs, :moderation_policy, moderation_policy()),
      access_policy:
        get_attr(attrs, :access_policy, AnsibleRelay.ForumHost.BoardAccessPolicy.default()),
      content_visibility: get_attr(attrs, :content_visibility, "public"),
      encryption_state:
        if(get_attr(attrs, :content_visibility, "public") == "end_to_end_encrypted",
          do: "rotation_required",
          else: "disabled"
        ),
      federation_policy: get_attr(attrs, :federation_policy, %{"mode" => "enabled"})
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
