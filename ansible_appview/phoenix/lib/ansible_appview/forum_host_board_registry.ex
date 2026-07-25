defmodule AnsibleAppview.ForumHostBoardRegistry do
  @moduledoc "Trusted Forum Host board identity lookup for legacy feed migration."

  alias AnsibleAppview.Ingest.RelayClient

  @spec legacy_hosted_board_id(String.t()) :: String.t() | nil
  def legacy_hosted_board_id(board_id) when is_binary(board_id) do
    relay_base_url = Application.fetch_env!(:ansible_appview, :relay_base_url)

    with {:ok, boards} <- RelayClient.fetch_hosted_boards(relay_base_url) do
      resolve_legacy_hosted_board_id(boards, board_id)
    end
  end

  def legacy_hosted_board_id(_board_id), do: nil

  @doc false
  def resolve_legacy_hosted_board_id(boards, board_id)
      when is_list(boards) and is_binary(board_id) do
    Enum.find_value(boards, fn board ->
      aliases = [
        to_string(board["board_id"] || ""),
        to_string(board["hosted_board_id"] || ""),
        to_string(board["slug"] || "")
      ]

      if board_id in aliases, do: board["hosted_board_id"]
    end)
  end
end
