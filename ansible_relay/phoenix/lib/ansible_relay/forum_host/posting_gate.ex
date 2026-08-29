defmodule AnsibleRelay.ForumHost.PostingGate do
  @moduledoc """
  Board-level `posting_policy["min_post_tier"]` enforcement.

  Both write chokepoints (signed ops from the app, web-session writes from
  the frontend) call `authorize_post/2` at acceptance time. The author's
  tier is resolved through `AnsibleRelay.DidAccountCache` on every call —
  the decision is never cached, so tier revocation takes effect
  immediately. Boards without a `min_post_tier` key are ungated.
  """

  alias AnsibleRelay.{DidAccountCache, Repo, ReputationTier}
  alias AnsibleRelay.Db.ForumHostBoard
  alias AnsibleRelay.ForumHost.{BoardAccessPolicy, BoardCapabilityRequest, Moderation, Store}

  @poll_creation_roles ~w(posters moderators owners)
  @deliberation_creation_roles ~w(posters moderators owners)

  @doc "Authorizes creating a poll embedded in a new thread."
  def authorize_poll_creation(conn, %ForumHostBoard{} = board, author_did) do
    case poll_creation_role(board) do
      "posters" ->
        authorize_board_post(conn, board, author_did)

      "moderators" ->
        if Moderation.moderator?(author_did, board),
          do: :ok,
          else: {:error, :poll_creation_requires_moderator}

      "owners" ->
        if Moderation.owner?(author_did, board),
          do: :ok,
          else: {:error, :poll_creation_requires_owner}
    end
  end

  def poll_creation_role(%ForumHostBoard{posting_policy: policy}) do
    role = Map.get(policy || %{}, "poll_creation") || Map.get(policy || %{}, :poll_creation)
    if role in @poll_creation_roles, do: role, else: "posters"
  end

  @doc "Authorizes creating a Board-owned deliberation."
  def authorize_deliberation_creation(conn, %ForumHostBoard{} = board, author_did) do
    case deliberation_creation_role(board) do
      "posters" ->
        authorize_board_post(conn, board, author_did)

      "moderators" ->
        if Moderation.moderator?(author_did, board),
          do: :ok,
          else: {:error, :deliberation_creation_requires_moderator}

      "owners" ->
        if Moderation.owner?(author_did, board),
          do: :ok,
          else: {:error, :deliberation_creation_requires_owner}
    end
  end

  def deliberation_creation_role(%ForumHostBoard{posting_policy: policy}) do
    role =
      Map.get(policy || %{}, "deliberation_creation") ||
        Map.get(policy || %{}, :deliberation_creation)

    if role in @deliberation_creation_roles, do: role, else: "posters"
  end

  @doc """
  Authorizes a thread/post write for `author_did`.

  Accepts a `%ForumHostBoard{}`, a hosted board id / slug, or `nil` (no
  board context, e.g. content not hosted by this Forum Host). Returns
  `:ok` or `{:error, :posting_requires_tier, required_tier, current_tier}`
  matching the reason-coded 403 rejection contract.
  """
  def authorize_post(nil, _author_did), do: :ok

  def authorize_post(board_id, author_did) when is_binary(board_id) do
    authorize_post(get_board(board_id), author_did)
  end

  def authorize_post(%ForumHostBoard{} = board, author_did) do
    case min_post_tier(board) do
      nil ->
        :ok

      required_tier ->
        current_tier = DidAccountCache.reputation_tier(author_did)

        if ReputationTier.meets?(current_tier, required_tier) do
          :ok
        else
          {:error, :posting_requires_tier, required_tier, current_tier}
        end
    end
  end

  def authorize_board_post(conn, %ForumHostBoard{} = board, author_did) do
    with :ok <- authorize_post(board, author_did),
         {:ok, requirement} <- BoardAccessPolicy.requirement_for(board.access_policy, :post) do
      case requirement do
        "public" ->
          :ok

        "posting_policy" ->
          :ok

        "board_moderator" ->
          {:error, :board_capability_required}

        _credential_requirement ->
          case BoardCapabilityRequest.authorize(conn, Integer.to_string(board.board_id), "post") do
            {:ok, _grant} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  def authorize_board_post(_conn, nil, _author_did), do: :ok

  @doc "Extracts `min_post_tier` from a board or posting policy map (nil = ungated)."
  def min_post_tier(%ForumHostBoard{posting_policy: policy}), do: min_post_tier(policy)

  def min_post_tier(%{} = policy) do
    case Map.get(policy, "min_post_tier") || Map.get(policy, :min_post_tier) do
      tier when is_binary(tier) -> tier
      _value -> nil
    end
  end

  def min_post_tier(_policy), do: nil

  @doc "Looks up a hosted board by canonical board ID, then legacy storage IDs."
  def get_board(board_id) when is_binary(board_id) do
    (canonical_board(board_id) ||
       Repo.get(ForumHostBoard, board_id) ||
       get_composite_board(board_id))
    |> then(fn
      %ForumHostBoard{} = board -> Store.activate_due_board_policy(board)
      nil -> nil
    end)
  end

  def get_board(_board_id), do: nil

  defp canonical_board(board_id) do
    case Integer.parse(board_id) do
      {id, ""} when id > 0 -> Repo.get_by(ForumHostBoard, board_id: id)
      _ -> nil
    end
  end

  # App projections use `<forum-host-node-id>_<board-id>` locally. Signed ops
  # preserve that local id, so resolve only the exact suffix after the first
  # separator. The suffix is normally the canonical numeric board ID, while
  # older records can still use the hosted-board primary key.
  defp get_composite_board(board_id) do
    case String.split(board_id, "_", parts: 2) do
      [_prefix, board_suffix] when board_suffix != "" ->
        canonical_board(board_suffix) || Repo.get(ForumHostBoard, board_suffix)

      _ ->
        nil
    end
  end
end
