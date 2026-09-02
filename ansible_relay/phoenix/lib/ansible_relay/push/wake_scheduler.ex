defmodule AnsibleRelay.Push.WakeScheduler do
  @moduledoc """
  Debounced, content-free wake-push scheduling (Phase B notifications).

  Triggers arrive as casts from the ingest paths (ops controller, messenger
  store), so wake scheduling is fire-and-forget: a sender or database failure
  can never affect the request path. The scheduler resolves the wake target:

    * `post` insert — the parent thread's create-op author (from the op log),
      category `"reply"`, self-replies skipped;
    * public `post` / `comment` insert — up to ten DIDs explicitly carried in
      the signed `mentionDids` payload, category `"mention"`, self-mentions
      skipped;
    * `follow` insert — the op's `entity_id` carries the target DID (see the
      app's `CrdtOpBuilder`), category `"follow"`, self-follows skipped;
    * messenger mailbox delivery — the recipient DID, category `"messenger"`,
      sender == recipient skipped.

  Wakes are debounced per (DID, device) in ETS with a trailing-edge window
  (default 30s, `:push_wake_debounce_ms`): the first trigger arms a timer,
  further triggers inside the window coalesce into it, and the flush re-reads
  the token row so an unregister inside the window cancels the send — a burst
  of replies/follows wakes a device once.

  The payload is exactly `%{"hint" => "sync"}`. Notification content is never
  pushed; the device syncs and composes notifications locally.
  """

  use GenServer

  require Logger

  alias AnsibleRelay.OpStore
  alias AnsibleRelay.Push.{PushSender, TokenRegistry}

  @wake_payload %{"hint" => "sync"}
  @default_debounce_ms 30_000
  @default_send_timeout_ms 10_000
  @table :push_wake_debounce

  # Supervises the fire-and-forget push-send tasks so a slow push endpoint can
  # never back up the scheduler mailbox.
  @task_supervisor AnsibleRelay.Push.WakeTaskSupervisor

  # --- Public API (fire-and-forget) ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Cast an accepted op. Reply/follow inserts targeting a registered DID schedule a wake."
  def op_accepted(op) when is_map(op) do
    GenServer.cast(__MODULE__, {:op_accepted, op})
  end

  @doc "Cast a stored mailbox message. The recipient's opted-in devices get a wake."
  def mailbox_delivered(sender_did, recipient_did) do
    GenServer.cast(__MODULE__, {:mailbox_delivered, sender_did, recipient_did})
  end

  @doc false
  def mention_recipients(payload, author_did) when is_map(payload) do
    mentions =
      case Map.get(payload, "mentionDids", []) do
        values when is_list(values) -> values
        _ -> []
      end

    mentions
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "did:") and &1 != author_did))
    |> Enum.uniq()
    |> Enum.take(10)
  end

  @doc false
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Wait for all in-flight wake-send tasks to finish. Test-only: sends now run in
  supervised tasks, so a test must drain them before asserting on the sender.
  """
  def drain(timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_drain(deadline)
  end

  defp do_drain(deadline) do
    children =
      case Process.whereis(@task_supervisor) do
        nil -> []
        _pid -> Task.Supervisor.children(@task_supervisor)
      end

    cond do
      children == [] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(10)
        do_drain(deadline)
    end
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :private])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:op_accepted, op}, state) do
    safely(fn -> handle_op(op) end)
    {:noreply, state}
  end

  def handle_cast({:mailbox_delivered, sender_did, recipient_did}, state) do
    safely(fn ->
      if sender_did != recipient_did do
        schedule_wakes(recipient_did, "messenger")
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:flush, subject_did, device_id}, state) do
    safely(fn -> flush(subject_did, device_id) end)
    {:noreply, state}
  end

  # --- Trigger resolution ---

  defp handle_op(%{entity_type: "post", op_type: "insert"} = op) do
    case decode_payload(op.payload) do
      {:ok, %{} = payload} ->
        schedule_mention_wakes(payload, op.author_did)
        schedule_reply_wake(payload, op.author_did)

      _ ->
        :ok
    end
  end

  defp handle_op(%{entity_type: "comment", op_type: "insert"} = op) do
    case decode_payload(op.payload) do
      {:ok, %{} = payload} -> schedule_mention_wakes(payload, op.author_did)
      _ -> :ok
    end
  end

  defp handle_op(%{entity_type: "follow", op_type: "insert"} = op) do
    # Follow ops carry the target DID as entity_id (app CrdtOpBuilder convention).
    if is_binary(op.entity_id) and op.entity_id != op.author_did do
      schedule_wakes(op.entity_id, "follow")
    else
      :ok
    end
  end

  defp handle_op(_op), do: :ok

  defp schedule_reply_wake(payload, reply_author_did) do
    with thread_id when is_binary(thread_id) <- payload["threadId"] || payload["thread_id"],
         author when is_binary(author) <- OpStore.create_op_author("thread", thread_id),
         true <- author != reply_author_did do
      schedule_wakes(author, "reply")
    else
      _ -> :ok
    end
  end

  defp schedule_mention_wakes(payload, author_did) do
    payload
    |> mention_recipients(author_did)
    |> Enum.each(&schedule_wakes(&1, "mention"))
  end

  defp schedule_wakes(subject_did, category) do
    subject_did
    |> TokenRegistry.devices_for(category)
    |> Enum.each(fn device ->
      key = {device.subject_did, device.device_id}

      if :ets.insert_new(@table, {key, category}) do
        Process.send_after(
          self(),
          {:flush, device.subject_did, device.device_id},
          debounce_ms()
        )
      end
    end)
  end

  defp flush(subject_did, device_id) do
    category =
      case :ets.lookup(@table, {subject_did, device_id}) do
        [{_key, cat}] -> cat
        _ -> "unknown"
      end

    :ets.delete(@table, {subject_did, device_id})

    # Re-read at flush time so an unregister inside the debounce window wins:
    # no row, no wake.
    case TokenRegistry.lookup(subject_did, device_id) do
      nil ->
        :ok

      device ->
        # The actual push HTTP call runs in a supervised, bounded-timeout task so
        # a slow/hung push endpoint cannot back up the scheduler mailbox. The
        # debounce/coalesce bookkeeping above still runs on the GenServer, so
        # per-(DID, device) coalescing is unchanged.
        dispatch_send(device, category)
        :ok
    end
  end

  defp dispatch_send(device, category) do
    Task.Supervisor.start_child(@task_supervisor, fn ->
      task =
        Task.Supervisor.async_nolink(@task_supervisor, fn ->
          PushSender.impl().send_wake(device.push_token, device.platform, @wake_payload)
        end)

      case Task.yield(task, send_timeout_ms()) || Task.shutdown(task, :brutal_kill) do
        {:ok, :ok} ->
          AnsibleRelay.Metrics.inc("relay_wake_sends_total", %{category: category})

        {:ok, {:error, reason}} ->
          Logger.warning(
            "Push.WakeScheduler: send_wake failed platform=#{device.platform} " <>
              "reason=#{inspect(reason)}"
          )

        nil ->
          Logger.warning("Push.WakeScheduler: send_wake timed out platform=#{device.platform}")

        {:exit, reason} ->
          Logger.warning(
            "Push.WakeScheduler: send_wake crashed platform=#{device.platform} " <>
              "reason=#{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  defp send_timeout_ms do
    Application.get_env(:ansible_relay, :push_wake_send_timeout_ms, @default_send_timeout_ms)
  end

  # Payloads may arrive as raw JSON or, per the app's CrdtOpBuilder convention,
  # as base64-encoded JSON (mirrors OpsController.decode_payload/1).
  defp decode_payload(payload) when is_map(payload), do: {:ok, payload}

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} ->
        {:ok, decoded}

      _ ->
        with {:ok, raw} <- Base.decode64(payload),
             {:ok, decoded} <- Jason.decode(raw) do
          {:ok, decoded}
        else
          _ -> :error
        end
    end
  end

  defp decode_payload(_payload), do: :error

  defp debounce_ms do
    Application.get_env(:ansible_relay, :push_wake_debounce_ms, @default_debounce_ms)
  end

  # Wake scheduling must never crash the scheduler or leak content into logs:
  # only the exception type is recorded.
  defp safely(fun) do
    fun.()
    :ok
  rescue
    error ->
      Logger.warning("Push.WakeScheduler: scheduling failed: #{inspect(error.__struct__)}")
      :ok
  end
end
