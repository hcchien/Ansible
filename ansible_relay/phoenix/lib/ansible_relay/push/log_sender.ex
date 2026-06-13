defmodule AnsibleRelay.Push.LogSender do
  @moduledoc """
  Default no-transport push sender: logs each wake at info level.

  The payload is content-free (`{"hint": "sync"}`) so logging it is safe; the
  push token itself is never logged (it is opaque but still a routable
  device address).
  """

  @behaviour AnsibleRelay.Push.PushSender

  require Logger

  @impl true
  def send_wake(_token, platform, payload) do
    Logger.info("Push.LogSender: wake platform=#{platform} payload=#{Jason.encode!(payload)}")
    :ok
  end
end
