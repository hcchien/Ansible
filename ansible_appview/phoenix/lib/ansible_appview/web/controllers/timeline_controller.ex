defmodule AnsibleAppview.Web.Controllers.TimelineController do
  @moduledoc "Following timeline + board feed read API."

  import Plug.Conn
  alias AnsibleAppview.{Metrics, Timeline}

  # POST /api/v1/timeline  body: {dids: [...], cursor?, limit?}
  # The follow set is read transiently and never logged or persisted.
  def timeline(conn, params) do
    Metrics.inc("appview_timeline_requests_total", %{kind: "following"})

    Metrics.time("appview_timeline_request_duration_seconds", %{kind: "following"}, fn ->
      do_timeline(conn, params)
    end)
  end

  defp do_timeline(conn, params) do
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

  # GET /api/v1/home?reader=did:...&cursor=&limit=
  # Server-materialized fan-out-on-write timeline for a single reader.
  def home(conn, params) do
    Metrics.inc("appview_timeline_requests_total", %{kind: "home"})

    Metrics.time("appview_timeline_request_duration_seconds", %{kind: "home"}, fn ->
      do_home(conn, params)
    end)
  end

  defp do_home(conn, params) do
    reader = params["reader"]

    cond do
      not (is_binary(reader) and reader != "") ->
        send_json(conn, 422, %{error: "reader_required"})

      true ->
        # The home feed discloses the reader's follow graph, so a caller may only
        # read its OWN feed. Authenticate via a signed request (see HomeAuth).
        case AnsibleAppview.HomeAuth.authorize(header_map(conn), reader) do
          :ok ->
            result =
              Timeline.home(
                reader,
                parse_int(params["cursor"]),
                parse_int(params["limit"]) || 50
              )

            send_json(conn, 200, result)

          {:error, :unknown_reader} ->
            send_json(conn, 403, %{error: "forbidden"})

          {:error, :unauthorized} ->
            send_json(conn, 401, %{error: "unauthorized"})
        end
    end
  end

  # req_headers are {lowercase_name, value} tuples; fold to a map for lookup.
  defp header_map(conn), do: Map.new(conn.req_headers)

  # GET /api/v1/board-feed?board_id=&cursor=&limit=
  def board_feed(conn, params) do
    Metrics.inc("appview_timeline_requests_total", %{kind: "board"})

    Metrics.time("appview_timeline_request_duration_seconds", %{kind: "board"}, fn ->
      do_board_feed(conn, params)
    end)
  end

  defp do_board_feed(conn, params) do
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

  @doc "GET /api/v1/thread/:thread_id — comments threaded under a content/thread id."
  def thread_feed(conn, params) do
    Metrics.inc("appview_timeline_requests_total", %{kind: "thread"})

    Metrics.time("appview_timeline_request_duration_seconds", %{kind: "thread"}, fn ->
      do_thread_feed(conn, params)
    end)
  end

  defp do_thread_feed(conn, params) do
    thread_id = params["thread_id"]

    if is_binary(thread_id) and thread_id != "" do
      result =
        Timeline.for_thread(
          thread_id,
          parse_int(params["cursor"]),
          parse_int(params["limit"]) || 50
        )

      send_json(conn, 200, result)
    else
      send_json(conn, 422, %{error: "thread_id_required"})
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
