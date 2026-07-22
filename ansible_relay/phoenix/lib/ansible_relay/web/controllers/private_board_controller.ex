defmodule AnsibleRelay.Web.Controllers.PrivateBoardController do
  @moduledoc "Capability- and DPoP-protected private-board key lifecycle endpoints."

  import Plug.Conn

  alias AnsibleRelay.ForumHost.{BoardCapabilityRequest, PrivateBoardKeys}

  def register_device(conn, board_id, params) do
    with {:ok, grant} <- BoardCapabilityRequest.authorize(conn, board_id, "key:read"),
         {:ok, key} <- PrivateBoardKeys.register_device(board_id, grant, params) do
      send_json(conn, 201, %{device_key: device_json(key)})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def devices(conn, board_id) do
    with {:ok, grant} <- BoardCapabilityRequest.authorize(conn, board_id, "moderate"),
         {:ok, board, devices} <- PrivateBoardKeys.list_active_devices(board_id, grant) do
      send_json(conn, 200, %{
        board_id: board.hosted_board_id,
        policy_version: board.access_policy_version,
        encryption_epoch: board.encryption_epoch,
        encryption_state: board.encryption_state,
        devices: devices
      })
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def activate_epoch(conn, board_id, params) do
    with {:ok, grant} <- BoardCapabilityRequest.authorize(conn, board_id, "moderate"),
         {:ok, epoch} <-
           PrivateBoardKeys.activate_epoch(
             board_id,
             grant,
             params["epoch"],
             params["policy_version"],
             params["envelopes"]
           ) do
      send_json(conn, 201, %{
        board_id: board_id,
        epoch: epoch.epoch,
        policy_version: epoch.policy_version,
        state: epoch.state
      })
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def current_envelope(conn, board_id) do
    with {:ok, grant} <- BoardCapabilityRequest.authorize(conn, board_id, "key:read"),
         {:ok, board, envelope} <- PrivateBoardKeys.current_envelope(board_id, grant) do
      send_json(conn, 200, %{
        board_id: board.hosted_board_id,
        epoch: board.encryption_epoch,
        policy_version: board.access_policy_version,
        envelope: envelope
      })
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def revoke_device(conn, board_id, device_key_id) do
    with {:ok, grant} <- BoardCapabilityRequest.authorize(conn, board_id, "moderate"),
         {:ok, key} <- PrivateBoardKeys.revoke_device(board_id, grant, device_key_id) do
      send_json(conn, 200, %{device_key: device_json(key), rotation_required: true})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp device_json(key) do
    %{
      device_key_id: key.device_key_id,
      agreement_public_key_hex: key.agreement_public_key_hex,
      public_key_hash: key.public_key_hash,
      policy_version: key.policy_version,
      state: key.state
    }
  end

  defp error(conn, :board_not_found), do: send_json(conn, 404, %{error: "board_not_found"})

  defp error(conn, reason)
       when reason in [
              :board_capability_required,
              :invalid_board_capability,
              :capability_expired,
              :board_capability_replay,
              :stale_policy
            ],
       do: send_json(conn, 403, %{error: Atom.to_string(reason)})

  defp error(conn, reason), do: send_json(conn, 422, %{error: error_string(reason)})

  defp error_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_string(reason), do: inspect(reason)

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
