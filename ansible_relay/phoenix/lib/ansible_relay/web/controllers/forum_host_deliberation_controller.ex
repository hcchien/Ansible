defmodule AnsibleRelay.Web.Controllers.ForumHostDeliberationController do
  @moduledoc "Board-authorized API for multi-statement deliberations and analysis exports."

  import Plug.Conn

  alias AnsibleRelay.ForumHost.{
    BoardAccessPolicy,
    BoardCapabilityRequest,
    Deliberations,
    Moderation,
    PostingGate,
    SignedIntent,
    Store
  }

  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def index(conn, board_id) do
    with board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- authorize_access(conn, board, :read) do
      send_json(conn, 200, %{deliberations: Deliberations.list(board)})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def show(conn, board_id, deliberation_id) do
    with board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- authorize_access(conn, board, :read),
         {:ok, deliberation} <- Deliberations.detail(board, deliberation_id) do
      send_json(conn, 200, %{deliberation: deliberation})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def create(conn, board_id, params) do
    if params["signature"],
      do: create_signed(conn, board_id, params),
      else: create_web(conn, board_id, params)
  end

  defp create_signed(conn, board_id, params) do
    with true <- params["board_id"] == board_id,
         {:ok, author_did} <-
           SignedIntent.verify_deliberation_intent(params, "create_deliberation"),
         board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- PostingGate.authorize_deliberation_creation(conn, board, author_did),
         {:ok, deliberation} <-
           Deliberations.create(board, params["deliberation"], author_did, params["intent_id"]) do
      send_json(conn, 201, %{deliberation: deliberation})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      false -> send_json(conn, 422, %{error: "invalid_deliberation"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp create_web(conn, board_id, params) do
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      with board when not is_nil(board) <- PostingGate.get_board(board_id),
           :ok <-
             PostingGate.authorize_deliberation_creation(conn, board, conn.assigns.verified_did),
           {:ok, deliberation} <-
             Deliberations.create(
               board,
               params["deliberation"] || params,
               conn.assigns.verified_did,
               params["intent_id"] || Ecto.UUID.generate()
             ) do
        send_json(conn, 201, %{deliberation: deliberation})
      else
        nil -> send_json(conn, 404, %{error: "board_not_found"})
        {:error, reason} -> send_error(conn, reason)
      end
    end
  end

  def create_statement(conn, board_id, deliberation_id, params) do
    if params["signature"],
      do: create_statement_signed(conn, board_id, deliberation_id, params),
      else: create_statement_web(conn, board_id, deliberation_id, params)
  end

  defp create_statement_signed(conn, board_id, deliberation_id, params) do
    with true <- params["board_id"] == board_id and params["deliberation_id"] == deliberation_id,
         {:ok, author_did} <-
           SignedIntent.verify_deliberation_intent(params, "submit_deliberation_statement"),
         board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- PostingGate.authorize_board_post(conn, board, author_did),
         {:ok, statement} <-
           Deliberations.submit_statement(
             board,
             deliberation_id,
             params["text"],
             author_did,
             params["intent_id"]
           ) do
      send_json(conn, 201, %{statement: statement})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      false -> send_json(conn, 422, %{error: "invalid_deliberation_statement"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp create_statement_web(conn, board_id, deliberation_id, params) do
    with {:ok, conn} <- web_post_session(conn),
         board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- PostingGate.authorize_board_post(conn, board, conn.assigns.verified_did),
         {:ok, statement} <-
           Deliberations.submit_statement(
             board,
             deliberation_id,
             params["text"],
             conn.assigns.verified_did,
             params["intent_id"] || Ecto.UUID.generate()
           ) do
      send_json(conn, 201, %{statement: statement})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def vote(conn, board_id, deliberation_id, statement_id, params) do
    if params["signature"],
      do: vote_signed(conn, board_id, deliberation_id, statement_id, params),
      else: vote_web(conn, board_id, deliberation_id, statement_id, params)
  end

  defp vote_signed(conn, board_id, deliberation_id, statement_id, params) do
    with true <-
           params["board_id"] == board_id and params["deliberation_id"] == deliberation_id and
             params["statement_id"] == statement_id,
         {:ok, author_did} <-
           SignedIntent.verify_deliberation_intent(params, "cast_deliberation_vote"),
         board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- PostingGate.authorize_board_post(conn, board, author_did),
         {:ok, response} <-
           Deliberations.cast_vote(
             board,
             deliberation_id,
             statement_id,
             params["stance"],
             author_did,
             params["intent_id"],
             params["supersedes_intent_id"]
           ) do
      send_json(conn, 200, %{response: response})
    else
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      false -> send_json(conn, 422, %{error: "invalid_deliberation_vote"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp vote_web(conn, board_id, deliberation_id, statement_id, params) do
    with {:ok, conn} <- web_post_session(conn),
         board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- PostingGate.authorize_board_post(conn, board, conn.assigns.verified_did),
         {:ok, response} <-
           Deliberations.cast_vote(
             board,
             deliberation_id,
             statement_id,
             params["stance"],
             conn.assigns.verified_did,
             params["intent_id"] || Ecto.UUID.generate(),
             params["supersedes_intent_id"]
           ) do
      send_json(conn, 200, %{response: response})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def withdraw_vote(conn, board_id, deliberation_id, statement_id, params) do
    if params["signature"] do
      with true <-
             params["board_id"] == board_id and params["deliberation_id"] == deliberation_id and
               params["statement_id"] == statement_id,
           {:ok, author_did} <-
             SignedIntent.verify_deliberation_intent(params, "withdraw_deliberation_vote"),
           board when not is_nil(board) <- PostingGate.get_board(board_id),
           :ok <- PostingGate.authorize_board_post(conn, board, author_did),
           {:ok, response} <-
             Deliberations.withdraw_vote(
               board,
               deliberation_id,
               statement_id,
               author_did,
               params["supersedes_intent_id"]
             ) do
        send_json(conn, 200, %{response: response})
      else
        nil -> send_json(conn, 404, %{error: "board_not_found"})
        false -> send_json(conn, 422, %{error: "invalid_deliberation_vote"})
        {:error, reason} -> send_error(conn, reason)
      end
    else
      with {:ok, conn} <- web_post_session(conn),
           board when not is_nil(board) <- PostingGate.get_board(board_id),
           :ok <- PostingGate.authorize_board_post(conn, board, conn.assigns.verified_did),
           {:ok, response} <-
             Deliberations.withdraw_vote(
               board,
               deliberation_id,
               statement_id,
               conn.assigns.verified_did,
               params["supersedes_intent_id"]
             ) do
        send_json(conn, 200, %{response: response})
      else
        {:halted, halted_conn} -> halted_conn
        nil -> send_json(conn, 404, %{error: "board_not_found"})
        {:error, reason} -> send_error(conn, reason)
      end
    end
  end

  def report(conn, board_id, deliberation_id) do
    with board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- authorize_access(conn, board, :read),
         {:ok, report} <- Deliberations.report(board, deliberation_id) do
      send_json(conn, 200, %{report: report})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def viewer_responses(conn, board_id, deliberation_id, params) do
    if params["signature"] do
      with true <- params["board_id"] == board_id and params["deliberation_id"] == deliberation_id,
           {:ok, viewer_did} <-
             SignedIntent.verify_deliberation_intent(params, "read_deliberation_responses"),
           board when not is_nil(board) <- PostingGate.get_board(board_id),
           :ok <- PostingGate.authorize_board_post(conn, board, viewer_did),
           {:ok, responses} <- Deliberations.viewer_responses(board, deliberation_id, viewer_did) do
        send_json(conn, 200, %{responses: responses})
      else
        nil -> send_json(conn, 404, %{error: "board_not_found"})
        false -> send_json(conn, 422, %{error: "invalid_deliberation_response_read"})
        {:error, reason} -> send_error(conn, reason)
      end
    else
      with {:ok, conn} <- web_post_session(conn),
           board when not is_nil(board) <- PostingGate.get_board(board_id),
           :ok <- PostingGate.authorize_board_post(conn, board, conn.assigns.verified_did),
           {:ok, responses} <-
             Deliberations.viewer_responses(board, deliberation_id, conn.assigns.verified_did) do
        send_json(conn, 200, %{responses: responses})
      else
        {:halted, halted_conn} -> halted_conn
        nil -> send_json(conn, 404, %{error: "board_not_found"})
        {:error, reason} -> send_error(conn, reason)
      end
    end
  end

  def export(conn, board_id, deliberation_id, params) do
    view = params["view"] || "report"
    action = if view == "pseudonymous_matrix", do: :analyze, else: :read

    if params["signature"] do
      export_signed(conn, board_id, deliberation_id, params, view, action)
    else
      export_web(conn, board_id, deliberation_id, view, action)
    end
  end

  defp export_signed(conn, board_id, deliberation_id, params, view, action) do
    with true <- params["board_id"] == board_id and params["deliberation_id"] == deliberation_id,
         {:ok, author_did} <-
           SignedIntent.verify_deliberation_intent(params, "export_deliberation"),
         board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- authorize_signed_access(conn, board, action, author_did),
         {:ok, export} <- Deliberations.export(board, deliberation_id, view) do
      send_json(conn, 201, %{export: export})
    else
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      false -> send_json(conn, 422, %{error: "invalid_deliberation_export"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp export_web(conn, board_id, deliberation_id, view, action) do
    with board when not is_nil(board) <- PostingGate.get_board(board_id),
         :ok <- authorize_access(conn, board, action),
         {:ok, export} <- Deliberations.export(board, deliberation_id, view) do
      send_json(conn, 201, %{export: export})
    else
      {:halted, halted_conn} -> halted_conn
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp authorize_signed_access(conn, board, action, author_did) do
    with {:ok, requirement} <- BoardAccessPolicy.requirement_for(board.access_policy, action) do
      case requirement do
        requirement when requirement in ["public", "posting_policy"] ->
          :ok

        "board_moderator" ->
          if Moderation.moderator?(author_did, board),
            do: :ok,
            else: {:error, :not_board_moderator}

        _credential_requirement ->
          case BoardCapabilityRequest.authorize(
                 conn,
                 Integer.to_string(board.board_id),
                 Atom.to_string(action)
               ) do
            {:ok, _grant} ->
              # The capability is already device-bound and board-scoped. The
              # Relay intentionally stores only a pairwise subject hash, not a
              # reversible DID, so possession is the privacy-preserving bind.
              :ok

            {:error, reason} ->
              {:error, reason}
          end
      end
    end
  end

  defp web_post_session(conn) do
    verified = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())
    if verified.halted, do: {:halted, verified}, else: {:ok, verified}
  end

  defp authorize_access(conn, board, action) do
    with {:ok, requirement} <- BoardAccessPolicy.requirement_for(board.access_policy, action) do
      case requirement do
        "public" ->
          :ok

        "posting_policy" ->
          :ok

        "board_moderator" ->
          verified = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

          cond do
            verified.halted -> {:halted, verified}
            Moderation.moderator?(verified.assigns.verified_did, board) -> :ok
            true -> {:error, :not_board_moderator}
          end

        _credential_requirement ->
          case BoardCapabilityRequest.authorize(
                 conn,
                 Integer.to_string(board.board_id),
                 Atom.to_string(action)
               ) do
            {:ok, _grant} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  defp send_error(conn, reason)
       when reason in [:board_not_found, :deliberation_not_found, :statement_not_found],
       do: send_json(conn, 404, %{error: Atom.to_string(reason)})

  defp send_error(conn, reason)
       when reason in [
              :board_capability_required,
              :invalid_board_capability,
              :capability_expired,
              :board_capability_replay,
              :credential_not_authorized,
              :credential_revoked,
              :not_board_moderator,
              :deliberation_creation_requires_moderator,
              :deliberation_creation_requires_owner
            ],
       do: send_json(conn, 403, %{error: Atom.to_string(reason)})

  defp send_error(conn, :stale_vote_intent),
    do: send_json(conn, 409, %{error: "stale_vote_intent"})

  defp send_error(conn, reason) when is_atom(reason),
    do: send_json(conn, 422, %{error: Atom.to_string(reason)})

  defp send_error(conn, _), do: send_json(conn, 422, %{error: "invalid_deliberation"})

  defp send_json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
