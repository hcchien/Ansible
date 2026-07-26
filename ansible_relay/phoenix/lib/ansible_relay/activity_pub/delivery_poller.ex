defmodule AnsibleRelay.ActivityPub.DeliveryPoller do
  @moduledoc """
  Periodic driver for outbound ActivityPub delivery.

  `DeliveryQueue.deliver_pending/2` had no non-test caller, so enqueued
  deliveries stayed `pending` forever, the exponential backoff was never
  honored, and there was no attempt cap. This GenServer closes that: on a timer
  it calls `deliver_pending` (which now only picks rows whose `next_retry_at`
  has elapsed and dead-letters after a max-attempt cap), POSTing each activity to
  its remote inbox over OTP's built-in `:httpc`.

  ## Deterministic gating

  Outbound federation is **not a v1 launch feature**. This poller only runs when
  explicitly enabled:

      config :ansible_relay, :activity_pub_delivery_enabled, true

  When disabled (the default) the process still starts as a supervised child but
  never polls — so the supervision tree is identical in both modes and the
  behavior is deterministic either way. Enqueued rows simply wait until the flag
  is turned on.
  """

  use GenServer
  require Logger

  alias AnsibleRelay.ActivityPub.{DeliveryQueue, HttpSignature}

  @default_interval_ms 60_000
  @default_batch_limit 50
  @default_http_timeout_ms 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Run one delivery pass synchronously. Intended for tests and manual pokes."
  def poll_now do
    GenServer.call(__MODULE__, :poll_now)
  end

  @impl true
  def init(_opts) do
    if enabled?() do
      schedule_poll()
      Logger.info("ActivityPub DeliveryPoller enabled (interval=#{interval_ms()}ms)")
    else
      Logger.info("ActivityPub DeliveryPoller disabled (:activity_pub_delivery_enabled=false)")
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    {:reply, run_pass(), state}
  end

  @impl true
  def handle_info(:poll, state) do
    if enabled?(), do: run_pass()
    schedule_poll()
    {:noreply, state}
  end

  # --- Internals ---

  defp run_pass do
    DeliveryQueue.deliver_pending(&post_activity/2, limit: batch_limit())
  rescue
    error ->
      Logger.warning("DeliveryPoller pass failed: #{inspect(error.__struct__)}")
      {:error, :pass_failed}
  end

  # Default outbound transport: POST the activity JSON to the remote inbox.
  # Returns {:ok, status} | {:error, reason} to match DeliveryQueue's client
  # contract (2xx delivered, 5xx retryable, other codes permanent).
  defp post_activity(attempt, activity) do
    remote_inbox = attempt.remote_inbox
    url = String.to_charlist(remote_inbox)
    body = Jason.encode!(activity)
    actor_uri = activity["actor"]

    with true <- is_binary(actor_uri),
         {:ok, headers} <- HttpSignature.headers(:post, remote_inbox, body, actor_uri) do
      request = {url, headers, ~c"application/activity+json", body}

      case :httpc.request(
             :post,
             request,
             [timeout: http_timeout_ms(), connect_timeout: 3_000],
             body_format: :binary
           ) do
        {:ok, {{_http, status, _reason}, _resp_headers, _resp_body}} ->
          {:ok, status}

        {:error, reason} ->
          {:error, reason}
      end
    else
      false -> {:error, :activity_actor_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, interval_ms())
  end

  defp enabled? do
    Application.get_env(:ansible_relay, :activity_pub_delivery_enabled, false)
  end

  defp interval_ms do
    Application.get_env(:ansible_relay, :activity_pub_delivery_interval_ms, @default_interval_ms)
  end

  defp batch_limit do
    Application.get_env(:ansible_relay, :activity_pub_delivery_batch_limit, @default_batch_limit)
  end

  defp http_timeout_ms do
    Application.get_env(:ansible_relay, :activity_pub_delivery_http_timeout_ms, @default_http_timeout_ms)
  end
end
