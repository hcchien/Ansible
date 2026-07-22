defmodule AnsibleRelay.Identity.AnchorAlerts do
  @moduledoc """
  Identity-alert wake pushes for the re-anchor hijack-resistance path
  (design §Re-Anchor Protocol: "immediately notifies ALL enrolled devices
  via the existing content-free wake push + a local notification
  (`identity_alert`)").

  Reuses the same content-free wake transport as `Push.WakeScheduler`: the
  payload is exactly `%{"hint" => "sync"}` (Base Rule 2 — no content through
  third-party push). It is sent IMMEDIATELY (not debounced) and to ALL
  registered devices of the DID regardless of per-category opt-in, because a
  silent account takeover is an irreversible identity harm
  (conflict-priority #1): the user must be told on every device they have.
  The reason code rides the metric label, never the push payload.
  """

  require Logger

  alias AnsibleRelay.Push.PushSender

  @wake_payload %{"hint" => "sync"}

  @doc "Alert all enrolled devices that a recovery re-anchor is pending."
  def recovery_pending(did) when is_binary(did) do
    alert(did, "recovery_pending")
  end

  @doc "Wake every enrolled device after a delayed recovery is promoted."
  def recovery_promoted(did) when is_binary(did) do
    alert(did, "recovery_promoted")
  end

  @doc "Wake every enrolled device after a recovery is vetoed and frozen."
  def recovery_vetoed(did) when is_binary(did) do
    alert(did, "recovery_vetoed")
  end

  defp alert(did, reason_code) do
    did
    |> all_devices()
    |> Enum.each(fn device ->
      case PushSender.impl().send_wake(device.push_token, device.platform, @wake_payload) do
        :ok ->
          AnsibleRelay.Metrics.inc("identity_alert_sends_total", %{reason: reason_code})

        {:error, reason} ->
          Logger.warning(
            "Identity.AnchorAlerts: send_wake failed platform=#{device.platform} " <>
              "reason=#{inspect(reason)}"
          )
      end
    end)

    :ok
  rescue
    error ->
      Logger.warning("Identity.AnchorAlerts: alert failed: #{inspect(error.__struct__)}")
      :ok
  end

  # Every registered device for the DID, across all categories — an identity
  # alert is not subject to category opt-out.
  defp all_devices(did) do
    import Ecto.Query
    alias AnsibleRelay.{Repo, Db.DevicePushToken}

    Repo.all(from(t in DevicePushToken, where: t.subject_did == ^did))
  rescue
    _ -> []
  end
end
