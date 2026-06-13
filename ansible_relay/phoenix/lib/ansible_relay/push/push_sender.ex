defmodule AnsibleRelay.Push.PushSender do
  @moduledoc """
  Behaviour for wake-push transports.

  Payloads handed to a sender are content-free by construction — the wake
  scheduler sends exactly `%{"hint" => "sync"}` (Constitution Base Rule 2:
  third-party push infrastructure is outside the user's trusted boundary, so
  no private content may flow through it). Adapters MUST forward the payload
  as-is and MUST NOT add content fields.

  The active sender is selected at runtime via app env:

      config :ansible_relay, :push_sender, AnsibleRelay.Push.LogSender

  `AnsibleRelay.Push.LogSender` is the default (no transport, logs at info).
  Real transports are config-time work; the adapters need:

    * **APNS** — token-based auth with `APNS_KEY_ID`, `APNS_TEAM_ID`,
      `APNS_KEY_P8` (the .p8 signing key), `APNS_TOPIC` (the app bundle id)
      and an environment flag (`APNS_ENVIRONMENT=development|production`).
      Wakes are background pushes: `apns-push-type: background`,
      `content-available: 1`, no alert/body.
    * **FCM** — HTTP v1 API with `FCM_PROJECT_ID` and
      `GOOGLE_APPLICATION_CREDENTIALS` (service-account JSON). Wakes are
      data-only messages (a `data` map, no `notification` block) so the
      client wakes silently and composes any visible notification locally.
  """

  @callback send_wake(token :: String.t(), platform :: String.t(), payload :: map()) ::
              :ok | {:error, term()}

  @doc "The configured sender module (defaults to `AnsibleRelay.Push.LogSender`)."
  def impl do
    Application.get_env(:ansible_relay, :push_sender, AnsibleRelay.Push.LogSender)
  end
end
