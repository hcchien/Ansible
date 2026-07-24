defmodule AnsibleAppview.ForumHostBoardRegistry do
  @moduledoc "Trusted Forum Host board identity lookup for legacy feed migration."

  alias AnsibleAppview.Ingest.RelayClient

  @spec legacy_hosted_board_id(String.t()) :: String.t() | nil
  def legacy_hosted_board_id(board_id) when is_binary(board_id) do
    relay_base_url = Application.fetch_env!(:ansible_appview, :relay_base_url)

    with {:ok, boards} <- RelayClient.fetch_hosted_boards(relay_base_url) do
      Enum.find_value(boards, fn board ->
        if to_string(board["board_id"] || "") == board_id do
          board["hosted_board_id"]
        end
      end)
    end
  end

  def legacy_hosted_board_id(_board_id), do: nil
end
