defmodule AnsibleAppview.Web.Controllers.TimelineController do
  @moduledoc "Following timeline + board feed read API."

  import Plug.Conn
  alias AnsibleAppview.Timeline

  # POST /api/v1/timeline  body: {dids: [...], cursor?, limit?}
  # The follow set is read transiently and never logged or persisted.
  def timeline(conn, params) do
    dids = params["dids"]

    if is_list(dids) do
      result =
        Timeline.for_authors(
          Enum.filter(dids, &is_binary/1),
          parse_int(params["cursor"]),
          parse_int(params["limit"]) || 50
        )

      send_json(conn, 200, result)
    else
      send_json(conn, 422, %{error: "dids_required"})
    end
  end

  # GET /api/v1/board-feed?board_id=&cursor=&limit=
  def board_feed(conn, params) do
    board_id = params["board_id"]

    if is_binary(board_id) and board_id != "" do
      result =
        Timeline.for_board(
          board_id,
          parse_int(params["cursor"]),
          parse_int(params["limit"]) || 50
        )

      send_json(conn, 200, result)
    else
      send_json(conn, 422, %{error: "board_id_required"})
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
