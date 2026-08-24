defmodule AnsibleRelay.Web.Controllers.WebPublicationController do
  @moduledoc "Content-bound Passkey publication ceremony for first-party web writes."

  import Plug.Conn

  alias AnsibleRelay.{AbuseDetector, WebPublication}
  alias AnsibleRelay.ForumHost.PostingGate
  alias AnsibleRelay.ForumHost.Store
  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def challenge(conn, params) do
    conn = VerifyWebSession.call(conn, [], audience: Store.base_url())

    if conn.halted do
      conn
    else
      operation = params["operation"]
      operation_hash = params["operation_hash"]

      with {:ok, options, board} <-
             WebPublication.prepare(
               conn.assigns.web_session,
               conn.assigns.web_session_id,
               operation,
               operation_hash
             ),
           :ok <- authorize_board(conn, board, operation) do
        send_json(conn, 201, options)
      else
        error -> send_error(conn, error)
      end
    end
  end

  def create(conn, params) do
    conn = VerifyWebSession.call(conn, [], audience: Store.base_url())

    if conn.halted do
      conn
    else
      operation = params["operation"]

      with {:ok, _normalized, _operation_hash, board} <-
             WebPublication.validate_operation(
               conn.assigns.web_session,
               operation,
               params["operation_hash"]
             ),
           :ok <- authorize_board(conn, board, operation),
           :ok <- AbuseDetector.check_did(conn.assigns.verified_did),
           {:ok, accepted, _board} <-
             WebPublication.accept(
               conn.assigns.web_session,
               conn.assigns.web_session_id,
               params["challenge_id"],
               operation,
               params["operation_hash"],
               params["credential"]
             ) do
        send_json(conn, 202, %{
          accepted: true,
          publication: WebPublication.serialize(accepted)
        })
      else
        error -> send_error(conn, error)
      end
    end
  end

  def show(conn, operation_id) do
    conn = VerifyWebSession.call(conn, [], audience: Store.base_url())

    if conn.halted do
      conn
    else
      case WebPublication.get_for_subject(operation_id, conn.assigns.verified_did) do
        {:ok, operation} ->
          send_json(conn, 200, %{publication: WebPublication.serialize(operation)})

        {:error, :not_found} ->
          send_json(conn, 404, %{error: "operation_not_found"})
      end
    end
  end

  defp authorize_board(conn, board, operation) do
    if operation["action"] in ["forum.publish", "forum.reply"] do
      if operation["action"] == "forum.publish" and is_map(operation["payload"]["poll"]) do
        PostingGate.authorize_poll_creation(conn, board, conn.assigns.verified_did)
      else
        PostingGate.authorize_board_post(conn, board, conn.assigns.verified_did)
      end
    else
      :ok
    end
  end

  defp send_error(conn, {:error, :not_enrolled}),
    do: send_json(conn, 409, %{error: "passkey_not_enrolled"})

  defp send_error(conn, {:error, :missing_required_scope}),
    do: send_json(conn, 403, %{error: "missing_required_scope"})

  defp send_error(conn, {:error, :session_subject_mismatch}),
    do: send_json(conn, 403, %{error: "session_subject_mismatch"})

  defp send_error(conn, {:error, :board_not_found}),
    do: send_json(conn, 404, %{error: "board_not_found"})

  defp send_error(conn, {:error, :operation_id_conflict}),
    do: send_json(conn, 409, %{error: "operation_id_conflict"})

  defp send_error(conn, {:error, :not_original_author}),
    do: send_json(conn, 403, %{error: "not_original_author"})

  defp send_error(conn, {:error, :original_content_not_found}),
    do: send_json(conn, 404, %{error: "original_content_not_found"})

  defp send_error(conn, {:error, :revision_conflict}),
    do: send_json(conn, 409, %{error: "revision_conflict"})

  defp send_error(conn, {:error, :board_policy_version_conflict}),
    do: send_json(conn, 409, %{error: "board_policy_version_conflict"})

  defp send_error(conn, {:error, :consumed_challenge}),
    do: send_json(conn, 409, %{error: "webauthn_challenge_consumed"})

  defp send_error(conn, {:error, :expired_challenge}),
    do: send_json(conn, 410, %{error: "webauthn_challenge_expired"})

  defp send_error(conn, {:error, :rate_limited, detail}),
    do: send_json(conn, 429, %{error: "rate_limited", detail: detail})

  defp send_error(conn, {:error, :posting_requires_tier, required, current}),
    do:
      send_json(conn, 403, %{
        error: "posting_requires_tier",
        required_tier: required,
        current_tier: current
      })

  defp send_error(conn, {:error, :thread_locked, reason_code}),
    do: send_json(conn, 403, %{error: "thread_locked", reason_code: reason_code})

  defp send_error(conn, {:error, reason})
       when reason in [
              :board_capability_required,
              :invalid_board_capability,
              :capability_expired,
              :board_capability_replay,
              :credential_not_authorized,
              :credential_revoked
            ],
       do: send_json(conn, 403, %{error: Atom.to_string(reason)})

  defp send_error(conn, {:error, reason})
       when reason in [
              :invalid_challenge,
              :webauthn_verification_failed,
              :operation_hash_mismatch,
              :payload_hash_mismatch,
              :operation_expired,
              :invalid_operation,
              :visibility_not_allowed,
              :audience_mismatch
            ],
       do: send_json(conn, 422, %{error: Atom.to_string(reason)})

  defp send_error(conn, _),
    do: send_json(conn, 422, %{error: "invalid_operation"})

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
