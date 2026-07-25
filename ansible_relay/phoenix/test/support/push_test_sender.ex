defmodule AnsibleRelay.Push.TestSender do
  @moduledoc """
  Test push sender: records every `send_wake/3` call in a named Agent.

  Configured as `:push_sender` in `config/test.exs`. Calls made while the
  Agent is not running (e.g. wakes triggered by unrelated test files with no
  registered tokens) are dropped silently.
  """

  @behaviour AnsibleRelay.Push.PushSender

  def start_link do
    # This is shared test infrastructure. It must not die when the individual
    # ExUnit process that first touched it exits while another case is running.
    case Agent.start(fn -> [] end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  def reset do
    {:ok, _pid} = start_link()
    Agent.update(__MODULE__, fn _calls -> [] end)
  end

  @doc "All recorded calls, oldest first: %{token, platform, payload}."
  def calls do
    Agent.get(__MODULE__, &Enum.reverse/1)
  end

  @impl true
  def send_wake(token, platform, payload) do
    if Process.whereis(__MODULE__) do
      Agent.update(
        __MODULE__,
        &[%{token: token, platform: platform, payload: payload} | &1]
      )
    end

    :ok
  end
end
