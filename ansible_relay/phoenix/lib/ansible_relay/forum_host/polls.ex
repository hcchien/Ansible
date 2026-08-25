defmodule AnsibleRelay.ForumHost.Polls do
  @moduledoc "Board-scoped, single-choice polls with privacy-preserving voter deduplication."

  import Ecto.Query

  alias AnsibleRelay.{OpStore, Repo}
  alias AnsibleRelay.Db.{ForumHostBoard, ForumHostPollVote}
  alias AnsibleRelay.ForumHost.PostingGate

  def cast_vote(%ForumHostBoard{} = board, poll_id, option_id, author_did) do
    with {:ok, poll} <- poll_for(board, poll_id),
         :ok <- open?(poll),
         :ok <- valid_option?(poll, option_id),
         {:ok, _vote} <-
           %ForumHostPollVote{}
           |> ForumHostPollVote.changeset(%{
             hosted_board_id: board.hosted_board_id,
             poll_id: poll_id,
             option_id: option_id,
             voter_hash: voter_hash(board.hosted_board_id, poll_id, author_did)
           })
           |> Repo.insert() do
      {:ok, results(board, poll_id, poll)}
    else
      {:error, %Ecto.Changeset{}} -> {:error, :already_voted}
      {:error, _} = error -> error
    end
  end

  def results(%ForumHostBoard{} = board, poll_id) do
    with {:ok, poll} <- poll_for(board, poll_id), do: {:ok, results(board, poll_id, poll)}
  end

  defp poll_for(board, poll_id) when is_binary(poll_id) and poll_id != "" do
    with %{payload: payload} <- OpStore.create_op("thread", poll_id),
         {:ok, %{} = thread} <- decode_payload(payload),
         true <- belongs_to_board?(thread["boardId"] || thread["board_id"], board),
         %{} = poll <- thread["poll"],
         true <- valid_poll?(poll) do
      {:ok, poll}
    else
      _ -> {:error, :poll_not_found}
    end
  end

  defp poll_for(_, _), do: {:error, :poll_not_found}

  # Thread ops preserve the App's local composite board ID
  # (`<forum-host-node-id>_<canonical-board-id>`). Resolve it through the same
  # exact canonical path as the posting gate, rather than comparing only the
  # legacy hosted key or raw numeric ID.
  defp belongs_to_board?(thread_board_id, %ForumHostBoard{} = board)
       when is_binary(thread_board_id) do
    case PostingGate.get_board(thread_board_id) do
      %ForumHostBoard{board_id: board_id} -> board_id == board.board_id
      nil -> false
    end
  end

  defp belongs_to_board?(_, _), do: false

  defp decode_payload(payload) do
    case Base.decode64(payload) do
      {:ok, decoded} -> Jason.decode(decoded)
      :error -> Jason.decode(payload)
    end
  end

  defp valid_poll?(%{"options" => options}) when is_list(options) and length(options) in 2..12,
    do:
      Enum.all?(options, fn
        %{"id" => id, "label" => label} ->
          is_binary(id) and id != "" and is_binary(label) and label != ""

        _ ->
          false
      end)

  defp valid_poll?(_), do: false

  defp open?(%{"closes_at" => closes_at}) when is_binary(closes_at) do
    case DateTime.from_iso8601(closes_at) do
      {:ok, time, _} ->
        if(DateTime.compare(time, DateTime.utc_now()) == :gt,
          do: :ok,
          else: {:error, :poll_closed}
        )

      _ ->
        {:error, :poll_closed}
    end
  end

  defp open?(_), do: :ok

  defp valid_option?(%{"options" => options}, option_id) do
    if Enum.any?(options, &(&1["id"] == option_id)), do: :ok, else: {:error, :invalid_poll_option}
  end

  defp results(board, poll_id, poll) do
    counts =
      from(v in ForumHostPollVote,
        where: v.hosted_board_id == ^board.hosted_board_id and v.poll_id == ^poll_id,
        group_by: v.option_id,
        select: {v.option_id, count(v.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      poll_id: poll_id,
      options:
        Enum.map(poll["options"], fn option ->
          %{id: option["id"], label: option["label"], votes: Map.get(counts, option["id"], 0)}
        end)
    }
  end

  defp voter_hash(board_id, poll_id, did),
    do:
      :crypto.hash(:sha256, "poll-v1:" <> board_id <> ":" <> poll_id <> ":" <> did)
      |> Base.encode16(case: :lower)
end
