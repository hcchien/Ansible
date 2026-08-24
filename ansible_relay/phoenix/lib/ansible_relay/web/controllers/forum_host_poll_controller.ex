defmodule AnsibleRelay.Web.Controllers.ForumHostPollController do
  @moduledoc "Authenticated voting rail for polls embedded in hosted-board threads."

  import Plug.Conn

  alias AnsibleRelay.ForumHost.{Polls, PostingGate}
  alias AnsibleRelay.ForumHost.Store
  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def create(conn, board_id, poll_id, %{"option_id" => option_id}) do
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      with board when not is_nil(board) <- PostingGate.get_board(board_id),
           :ok <- PostingGate.authorize_board_post(conn, board, conn.assigns.verified_did),
           {:ok, result} <- Polls.cast_vote(board, poll_id, option_id, conn.assigns.verified_did) do
        send_json(conn, 201, %{vote: %{accepted: true}, poll: result})
      else
        nil -> send_json(conn, 404, %{error: "board_not_found"})
        {:error, reason} -> send_error(conn, reason)
      end
    end
  end

  def create(conn, _board_id, _poll_id, _params),
    do: send_json(conn, 422, %{error: "invalid_poll_option"})

  def show(conn, board_id, poll_id) do
    with board when not is_nil(board) <- PostingGate.get_board(board_id),
         {:ok, result} <- Polls.results(board, poll_id) do
      send_json(conn, 200, %{poll: result})
    else
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, :poll_not_found} -> send_json(conn, 404, %{error: "poll_not_found"})
    end
  end

  defp send_error(conn, reason)
       when reason in [:already_voted, :poll_closed, :invalid_poll_option],
       do:
         send_json(conn, if(reason == :already_voted, do: 409, else: 422), %{
           error: Atom.to_string(reason)
         })

  defp send_error(conn, reason)
       when reason in [
              :posting_requires_tier,
              :board_capability_required,
              :invalid_board_capability,
              :capability_expired,
              :credential_not_authorized,
              :credential_revoked
            ],
       do: send_json(conn, 403, %{error: Atom.to_string(reason)})

  defp send_error(conn, {:posting_requires_tier, required_tier, current_tier}) do
    send_json(conn, 403, %{
      error: "posting_requires_tier",
      required_tier: required_tier,
      current_tier: current_tier
    })
  end

  defp send_error(conn, _), do: send_json(conn, 422, %{error: "invalid_poll_vote"})

  defp send_json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
