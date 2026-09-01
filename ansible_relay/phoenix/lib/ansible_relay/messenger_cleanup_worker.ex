defmodule AnsibleRelay.MessengerCleanupWorker do
  @moduledoc """
  Bounded, periodic deletion of expired Messenger ciphertext and ACK rows.

  Every batch locks rows with `FOR UPDATE SKIP LOCKED`, so multiple Relay
  instances can safely run the worker without electing a process-local leader.
  Work per tick is bounded to protect mailbox latency and the Cloud SQL pool.
  """

  use GenServer

  require Logger

  alias AnsibleRelay.{MessengerStore, Metrics}

  @default_interval_ms 300_000
  @default_batch_size 1_000
  @default_max_batches 10

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Run one bounded cleanup cycle synchronously."
  def run_once do
    GenServer.call(__MODULE__, :run_once, :infinity)
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, interval_ms()),
      batch_size: Keyword.get(opts, :batch_size, batch_size()),
      max_batches: Keyword.get(opts, :max_batches, max_batches())
    }

    schedule(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:run_once, _from, state) do
    {:reply, cleanup(state), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup(state)
    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp cleanup(state) do
    deleted = delete_batches(state.batch_size, state.max_batches, 0)
    Metrics.inc("messenger_cleanup_runs_total", %{result: "success"})

    if deleted > 0 do
      Metrics.inc("messenger_cleanup_deleted_total", %{}, deleted)
    end

    {:ok, deleted}
  rescue
    error ->
      Metrics.inc("messenger_cleanup_runs_total", %{result: "error"})
      Logger.warning("Messenger cleanup failed error=#{inspect(error.__struct__)}")
      {:error, :cleanup_failed}
  end

  defp delete_batches(_batch_size, 0, total), do: total

  defp delete_batches(batch_size, batches_left, total) do
    deleted = MessengerStore.purge_expired_messages(batch_size)
    next_total = total + deleted

    if deleted < batch_size do
      next_total
    else
      delete_batches(batch_size, batches_left - 1, next_total)
    end
  end

  defp schedule(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule(_interval_ms), do: :ok

  defp interval_ms do
    Application.get_env(:ansible_relay, :messenger_cleanup_interval_ms, @default_interval_ms)
  end

  defp batch_size do
    Application.get_env(:ansible_relay, :messenger_cleanup_batch_size, @default_batch_size)
  end

  defp max_batches do
    Application.get_env(:ansible_relay, :messenger_cleanup_max_batches, @default_max_batches)
  end
end
