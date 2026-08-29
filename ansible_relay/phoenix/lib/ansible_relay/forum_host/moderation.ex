defmodule AnsibleRelay.ForumHost.Moderation do
  @moduledoc """
  Host-level content reporting and board moderation.

  Implements the constitution's mandatory moderation elements (Base Rules
  6/7): every report and action carries a reason code from the fixed
  `AnsibleRelay.ForumHost.ReportReason` enum; every action is written to the
  `forum_host_moderation_actions` audit table (time-stamped, attributed to a
  moderator DID, reason-coded); and all effects are host-scoped — they alter
  this host's board projection and distribution surfaces only, never the
  author's local copy or other distribution paths. The audit table is the
  single source of truth for projection effects (tombstones, thread locks).

  Moderator model (MVP — board owner resolves to the host owner): a DID
  moderates a board when it is
    1. the host owner DID (`:forum_host_owner_did` application env),
    2. the DID that created the board (the accepted `create_board` intent), or
    3. listed in the board's `moderation_policy["moderators"]` (extension
       point for delegated moderators; no role-management UI in MVP).
  """

  import Ecto.Query

  alias AnsibleRelay.Repo

  alias AnsibleRelay.Db.{
    ForumHostAcceptedIntent,
    ForumHostBoard,
    ForumHostModerationAction,
    ForumHostReport
  }

  alias AnsibleRelay.ForumHost.{PostingGate, ReportRateLimiter, ReportReason}

  @lock_actions ~w(lock_thread unlock_thread)
  @remove_action "remove_post_from_board"
  @hide_context_note_action "hide_context_note"

  # --- Reports ---

  @doc """
  Files a report from either rail (signed intent or web session).

  Returns `{:ok, :created, report}`, `{:ok, :duplicate, report}` (same
  reporter + same target with an open report collapses), or
  `{:error, :invalid_reason_code | :unknown_target}` /
  `{:error, :rate_limited, detail}`. Duplicates collapse before the rate
  limiter runs, so re-reporting the same target never consumes a token;
  malformed reports never consume one either.
  """
  def create_report(attrs) do
    with :ok <- ReportReason.validate(attrs[:reason_code], attrs[:note]),
         {:ok, board} <- resolve_board(attrs[:board_id]),
         :ok <- validate_target(attrs[:target_kind], attrs[:target_ref]) do
      attrs = %{
        target_kind: attrs[:target_kind],
        target_ref: attrs[:target_ref],
        board_id: board.hosted_board_id,
        reporter_did: attrs[:reporter_did],
        reason_code: attrs[:reason_code],
        note: attrs[:note],
        status: "open"
      }

      case open_report(attrs.reporter_did, attrs.target_kind, attrs.target_ref) do
        %ForumHostReport{} = existing -> {:ok, :duplicate, existing}
        nil -> rate_limited_insert(attrs)
      end
    end
  end

  @doc """
  Lists reports across every board the DID moderates (`status` filters by
  report status; `"all"` lists everything). DIDs that moderate nothing get
  `{:error, :not_board_moderator}`.
  """
  def list_reports(moderator_did, status \\ "open") do
    with {:ok, query} <- moderated_scope(ForumHostReport, moderator_did) do
      reports =
        query
        |> maybe_status(status)
        |> order_by([r], desc: r.id)
        |> Repo.all()

      {:ok, reports}
    end
  end

  # --- Moderation actions (audit trail + report transitions) ---

  @doc """
  Records a moderator action. Validates the action and reason enums, board
  existence, and moderator authorization; writes the audit row and applies the
  report status transitions (`open -> actioned | dismissed`) atomically.
  """
  def create_action(attrs) do
    with :ok <- validate_action_name(attrs[:action]),
         :ok <- validate_action_reason(attrs[:reason_code]),
         {:ok, board} <- resolve_board(attrs[:board_id]),
         :ok <- authorize_moderator(attrs[:moderator_did], board),
         :ok <- validate_target_ref(attrs[:target_ref]),
         {:ok, report} <- resolve_report(attrs[:action], attrs[:report_id]) do
      insert_action(
        %{
          action: attrs[:action],
          target_ref: attrs[:target_ref],
          board_id: board.hosted_board_id,
          moderator_did: attrs[:moderator_did],
          reason_code: attrs[:reason_code],
          report_id: report && report.id
        },
        report
      )
    end
  end

  @doc "Lists the audit trail across every board the DID moderates."
  def list_actions(moderator_did) do
    with {:ok, query} <- moderated_scope(ForumHostModerationAction, moderator_did) do
      {:ok, query |> order_by([a], desc: a.id) |> Repo.all()}
    end
  end

  @doc "Returns true when the DID may moderate the board (see moduledoc)."
  def moderator?(did, %ForumHostBoard{} = board) when is_binary(did) do
    host_owner?(did) or board_creator?(did, board.hosted_board_id) or
      did in policy_moderators(board)
  end

  def moderator?(_did, _board), do: false

  @doc "Returns whether the DID owns this board or its first-party host."
  def owner?(did, %ForumHostBoard{} = board) when is_binary(did),
    do: host_owner?(did) or board_creator?(did, board.hosted_board_id)

  def owner?(_did, _board), do: false

  # --- Projection effects (public read surface + posting chokepoints) ---

  @doc """
  Public, reason-coded moderation state for a board: removal tombstone refs
  and locked threads. Tombstones are public by design — the affected author
  must be able to see the action and its reason (Base Rule 6). Notes are
  never included here.
  """
  def moderation_state(board_id) do
    %{
      removed_posts:
        board_id
        |> removal_map()
        |> Enum.sort()
        |> Enum.map(fn {ref, reason} -> %{target_ref: ref, reason_code: reason} end),
      locked_threads:
        board_id
        |> lock_map()
        |> Enum.sort()
        |> Enum.map(fn {thread_id, reason} -> %{thread_id: thread_id, reason_code: reason} end),
      hidden_context_notes:
        board_id
        |> hidden_context_note_map()
        |> Enum.sort()
        |> Enum.map(fn {note_id, reason} -> %{note_id: note_id, reason_code: reason} end)
    }
  end

  @doc "Host-scoped reason when a context note is hidden from one board."
  def context_note_hidden_reason(_note_id, nil), do: nil

  def context_note_hidden_reason(note_id, board_id)
      when is_binary(note_id) and is_binary(board_id) do
    hidden_context_note_map(board_id, [note_id])[note_id]
  end

  def context_note_hidden_reason(_note_id, _board_id), do: nil

  @doc """
  Rejects new posts into a locked thread. Called from the same chokepoints as
  `AnsibleRelay.ForumHost.PostingGate` (signed ops and web-session writes).
  """
  def authorize_thread_post(thread_id) when is_binary(thread_id) do
    case lock_map(nil, [thread_id]) do
      %{^thread_id => reason_code} -> {:error, :thread_locked, reason_code}
      _state -> :ok
    end
  end

  def authorize_thread_post(_thread_id), do: :ok

  @doc """
  Applies moderation effects to served op listings: removed posts become
  tombstones (payload and signature stripped, `removed: true` + reason code)
  and locked threads carry `locked: true` + lock reason code. The underlying
  op rows are untouched — only this host's projection changes.
  """
  def overlay_ops(ops) when is_list(ops) do
    entity_ids = ops |> Enum.map(& &1.entity_id) |> Enum.uniq()

    case entity_ids do
      [] ->
        ops

      ids ->
        removed = removal_map(nil, ids)
        locked = lock_map(nil, ids)
        Enum.map(ops, &overlay_op(&1, removed, locked))
    end
  end

  defp overlay_op(op, removed, locked) do
    lock_reason = if op.entity_type == "thread", do: locked[op.entity_id]

    cond do
      reason = removed[op.entity_id] ->
        op
        |> Map.put(:payload, nil)
        |> Map.put(:signature, nil)
        |> Map.put(:removed, true)
        |> Map.put(:reason_code, reason)

      lock_reason ->
        op
        |> Map.put(:locked, true)
        |> Map.put(:lock_reason_code, lock_reason)

      true ->
        op
    end
  end

  # --- Report helpers ---

  defp rate_limited_insert(attrs) do
    with :ok <- ReportRateLimiter.check_reporter(attrs.reporter_did) do
      %ForumHostReport{}
      |> ForumHostReport.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, report} ->
          {:ok, :created, report}

        {:error, changeset} ->
          # Concurrent duplicate hit the partial unique index — collapse.
          case open_report(attrs.reporter_did, attrs.target_kind, attrs.target_ref) do
            %ForumHostReport{} = existing -> {:ok, :duplicate, existing}
            nil -> {:error, changeset_error(changeset)}
          end
      end
    end
  end

  defp open_report(reporter_did, target_kind, target_ref) do
    Repo.one(
      from(r in ForumHostReport,
        where:
          r.reporter_did == ^reporter_did and r.target_kind == ^target_kind and
            r.target_ref == ^target_ref and r.status == "open",
        limit: 1
      )
    )
  end

  defp resolve_board(board_id) do
    case PostingGate.get_board(board_id) do
      nil -> {:error, :unknown_target}
      board -> {:ok, board}
    end
  end

  # An unknown target kind or a blank target ref cannot be resolved to
  # reportable content, so both map to :unknown_target (the contract's only
  # target-shaped error). Target refs are op entity ids; existence in the op
  # log is not required because web-rail threads are not persisted as ops.
  defp validate_target(target_kind, target_ref) do
    if target_kind in ForumHostReport.target_kinds() and present?(target_ref) do
      :ok
    else
      {:error, :unknown_target}
    end
  end

  defp validate_target_ref(target_ref) do
    if present?(target_ref), do: :ok, else: {:error, :unknown_target}
  end

  defp changeset_error(%Ecto.Changeset{errors: errors}) do
    if Keyword.has_key?(errors, :reason_code), do: :invalid_reason_code, else: :unknown_target
  end

  defp maybe_status(query, "all"), do: query
  defp maybe_status(query, status) when is_binary(status), do: where(query, status: ^status)
  defp maybe_status(query, _status), do: where(query, status: "open")

  # --- Action helpers ---

  defp validate_action_name(action) do
    if action in ForumHostModerationAction.actions(), do: :ok, else: {:error, :invalid_action}
  end

  # Actions carry no note, so only the enum membership applies here.
  defp validate_action_reason(reason_code) do
    if ReportReason.valid?(reason_code), do: :ok, else: {:error, :invalid_reason_code}
  end

  defp authorize_moderator(did, board) do
    if is_binary(did) and moderator?(did, board), do: :ok, else: {:error, :not_board_moderator}
  end

  # dismiss_report acts on a report, so it requires one; other actions take an
  # optional report_id linking the action back to the originating report.
  defp resolve_report("dismiss_report", nil), do: {:error, :unknown_report}
  defp resolve_report(_action, nil), do: {:ok, nil}

  defp resolve_report(_action, report_id) do
    case Repo.get(ForumHostReport, report_id) do
      nil -> {:error, :unknown_report}
      report -> {:ok, report}
    end
  end

  defp insert_action(attrs, report) do
    Repo.transaction(fn ->
      action =
        %ForumHostModerationAction{}
        |> ForumHostModerationAction.changeset(attrs)
        |> Repo.insert!()

      transition_reports(action, report)
      action
    end)
  end

  # open -> dismissed for dismiss_report; open -> actioned for the referenced
  # report and (for remove/lock) every other open report on the same target,
  # so acting once clears the whole queue entry.
  defp transition_reports(%{action: "dismiss_report"} = action, report) do
    set_report_status(report || %ForumHostReport{id: action.report_id}, "dismissed")
  end

  defp transition_reports(%{action: action_name} = action, report)
       when action_name in ["remove_post_from_board", "lock_thread", "hide_context_note"] do
    if report, do: set_report_status(report, "actioned")

    Repo.update_all(
      from(r in ForumHostReport,
        where:
          r.target_ref == ^action.target_ref and r.board_id == ^action.board_id and
            r.status == "open"
      ),
      set: [status: "actioned", updated_at: DateTime.utc_now()]
    )
  end

  defp transition_reports(_action, nil), do: :ok
  defp transition_reports(_action, report), do: set_report_status(report, "actioned")

  defp set_report_status(%ForumHostReport{id: id}, status) when not is_nil(id) do
    Repo.update_all(from(r in ForumHostReport, where: r.id == ^id),
      set: [status: status, updated_at: DateTime.utc_now()]
    )
  end

  defp set_report_status(_report, _status), do: :ok

  # --- Moderator scope ---

  defp moderated_scope(schema, did) do
    case moderated_board_ids(did) do
      :none -> {:error, :not_board_moderator}
      :all -> {:ok, from(row in schema)}
      {:some, ids} -> {:ok, from(row in schema, where: row.board_id in ^ids)}
    end
  end

  defp moderated_board_ids(did) when is_binary(did) do
    if host_owner?(did) do
      :all
    else
      ids = Enum.uniq(created_board_ids(did) ++ policy_moderated_board_ids(did))
      if ids == [], do: :none, else: {:some, ids}
    end
  end

  defp moderated_board_ids(_did), do: :none

  defp host_owner?(did) do
    case host_owner_did() do
      owner when is_binary(owner) -> owner == did
      _missing -> false
    end
  end

  defp host_owner_did do
    Application.get_env(:ansible_relay, :forum_host_owner_did)
  end

  defp board_creator?(did, hosted_board_id) do
    Repo.exists?(creator_intents(did) |> where([i], i.result_id == ^hosted_board_id))
  end

  defp created_board_ids(did) do
    Repo.all(creator_intents(did) |> select([i], i.result_id))
  end

  defp creator_intents(did) do
    from(i in ForumHostAcceptedIntent,
      where:
        i.author_did == ^did and i.action == "create_board" and
          i.result_kind == "forum_host_board"
    )
  end

  defp policy_moderated_board_ids(did) do
    Repo.all(
      from(b in ForumHostBoard,
        where:
          fragment(
            "? @> ?",
            b.moderation_policy,
            type(^%{"moderators" => [did]}, :map)
          ),
        select: b.hosted_board_id
      )
    )
  end

  defp policy_moderators(%ForumHostBoard{moderation_policy: %{} = policy}) do
    case Map.get(policy, "moderators") do
      moderators when is_list(moderators) -> Enum.filter(moderators, &is_binary/1)
      _value -> []
    end
  end

  defp policy_moderators(_board), do: []

  # --- Effect state (derived from the audit trail) ---

  # target_ref => reason_code for every removed post (latest action wins; no
  # un-remove action exists in v1).
  defp removal_map(board_id, target_refs \\ nil) do
    ForumHostModerationAction
    |> where([a], a.action == @remove_action)
    |> maybe_board(board_id)
    |> maybe_targets(target_refs)
    |> order_by([a], asc: a.id)
    |> Repo.all()
    |> Map.new(fn a -> {a.target_ref, a.reason_code} end)
  end

  # thread_id => reason_code for threads whose latest lock/unlock is a lock.
  defp lock_map(board_id, target_refs \\ nil) do
    ForumHostModerationAction
    |> where([a], a.action in @lock_actions)
    |> maybe_board(board_id)
    |> maybe_targets(target_refs)
    |> order_by([a], asc: a.id)
    |> Repo.all()
    |> Enum.reduce(%{}, fn action, acc ->
      case action.action do
        "lock_thread" -> Map.put(acc, action.target_ref, action.reason_code)
        "unlock_thread" -> Map.delete(acc, action.target_ref)
      end
    end)
  end

  defp hidden_context_note_map(board_id, target_refs \\ nil) do
    ForumHostModerationAction
    |> where([a], a.action == @hide_context_note_action)
    |> maybe_board(board_id)
    |> maybe_targets(target_refs)
    |> order_by([a], asc: a.id)
    |> Repo.all()
    |> Map.new(fn action -> {action.target_ref, action.reason_code} end)
  end

  defp maybe_board(query, nil), do: query
  defp maybe_board(query, board_id), do: where(query, [a], a.board_id == ^board_id)

  defp maybe_targets(query, nil), do: query
  defp maybe_targets(query, refs), do: where(query, [a], a.target_ref in ^refs)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
