defmodule AnsibleAppview.Web.Controllers.ExternalController do
  @moduledoc """
  Per-board external read API (inbound federation, design 2026-06-13 D3/D4,
  Task 4b-1).

  `GET /api/v1/boards/:board_id/external` — the **only** path that returns
  external (`source = "activitypub"`) content, scoped to the curated sources
  mapped to that board, newest-first. Every other read requires
  `sig_verified == true`; external items carry `sig_verified = false`, so they are
  absent from the verified timeline/discovery surfaces by construction.

  ## Gating boundary — IMPORTANT

  The CALLER is responsible for only calling this endpoint when
  `board.external_inclusion` (the relay forum-host board policy) AND the user
  opted in (per-user `allow-external` setting, conservative default). The AppView
  serves the lane unconditionally; the board/user gating lives at the relay policy
  + client per design D4 — it is not enforced here. See
  `AnsibleAppview.External` for the full boundary note.
  """

  import Plug.Conn
  alias AnsibleAppview.{External, Metrics}

  # GET /api/v1/boards/:board_id/external?cursor=&limit=
  def board_external(conn, params) do
    board_id = params["board_id"]

    if is_binary(board_id) and board_id != "" do
      Metrics.inc("external_read_requests_total", %{board: board_id})

      result =
        External.for_board(
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
