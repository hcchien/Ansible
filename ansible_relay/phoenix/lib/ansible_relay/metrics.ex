defmodule AnsibleRelay.Metrics do
  @moduledoc """
  Observability baseline (service architecture plan, Phase 0 — closes G17).

  A dependency-free Prometheus metrics registry: counters, gauges, and
  histograms live in a public ETS table owned by this GenServer, instrumentation
  points call `inc/2`, `set/2`, and `observe/3` directly (no telemetry handler
  indirection), and `render/0` produces Prometheus text-format output served at
  `GET /metrics`.

  The same GenServer runs a periodic poller for gauge series that are sampled
  rather than incremented inline — the op-table row count today, with hooks for
  the later phases' lag/queue-depth gauges.

  Concurrency: counter/histogram updates use `:ets.update_counter/4` (atomic,
  lock-free) against a `:public` table with write concurrency, so distinct series
  update fully in parallel and never serialize through the GenServer mailbox. The
  process exists only to own the table and drive the poller.

  ## Exposed series (relay)

    * `relay_op_ingest_total{entity_type,op_type}` — accepted op ingests
    * `relay_op_table_rows` (gauge) — rows in the `ops` table, polled
    * `relay_delta_requests_total` — `GET /api/v1/ops/delta` requests
    * `relay_delta_request_duration_seconds` (histogram) — delta latency
    * `relay_signature_verifications_total{result}` — op signature pass/fail
    * `relay_abuse_rejections_total{subject_type}` — abuse-limiter rejections
    * `relay_wake_sends_total{category}` — push wake-scheduler sends
    * `relay_reports_total{rail}` — report intake (signed-intent / web-session)
    * `relay_snapshot_generated_total` — signed op-snapshots generated (Phase 2.3)
    * `relay_snapshot_cursor` (gauge) — cursor (log_id) of the latest snapshot
    * `identity_reanchor_total{reason}` — accepted identity re-anchors (Task 4)
    * `identity_recovery_pending_total` — recovery anchors entering the grace window
    * `identity_veto_total` — pending recovery anchors vetoed (account frozen)
    * `identity_alert_sends_total{reason}` — identity-alert wake pushes sent
  """

  use GenServer
  require Logger

  @table :ansible_relay_metrics
  # Default latency buckets in seconds (Prometheus convention, web-request scale).
  @buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
  @default_poll_interval_ms 15_000

  # Metric metadata drives the HELP/TYPE headers in the rendered output. Every
  # series a phase references is declared here so `/metrics` lists it (at 0)
  # even before the first event — making the metric discoverable and the later
  # phases' exit criteria queryable from day one.
  @metric_defs %{
    "relay_op_ingest_total" => {:counter, "Accepted op ingests by entity and op type."},
    "relay_op_table_rows" => {:gauge, "Current row count of the relay ops table."},
    "relay_delta_requests_total" => {:counter, "Delta-pull endpoint requests."},
    "relay_delta_request_duration_seconds" =>
      {:histogram, "Delta-pull endpoint request latency in seconds."},
    "relay_signature_verifications_total" =>
      {:counter, "Op Ed25519 signature verifications by result (pass/fail)."},
    "relay_abuse_rejections_total" =>
      {:counter, "Abuse-limiter rejections by subject type (did/peer)."},
    "relay_wake_sends_total" => {:counter, "Push wake-scheduler sends by category."},
    "relay_reports_total" => {:counter, "Forum-host report intakes by rail."},
    "community_notes_rating_rate_limited_total" =>
      {:counter, "Community Note rating rate-limit rejections by reputation tier."},
    "relay_snapshot_generated_total" => {:counter, "Signed op-snapshots generated (Phase 2.3)."},
    "relay_snapshot_cursor" => {:gauge, "Cursor (log_id) of the latest published op-snapshot."},
    "identity_reanchor_total" => {:counter, "Identity re-anchors accepted, by reason."},
    "identity_recovery_pending_total" =>
      {:counter, "Recovery re-anchors entering the grace window (pending)."},
    "identity_veto_total" => {:counter, "Pending recovery anchors vetoed (account frozen)."},
    "identity_alert_sends_total" =>
      {:counter, "Identity-alert wake pushes sent to enrolled devices, by reason."},
    # Constitutional product measurement (ProductPulse) — aggregate-only.
    "elix_registered_dids" => {:gauge, "Registered DID accounts on this relay."},
    "elix_active_authors" =>
      {:gauge, "Distinct authors with ≥1 op in the window (aggregate only)."},
    "elix_active_boards" =>
      {:gauge, "Distinct boards with thread/post activity in the window."},
    "elix_new_authors" =>
      {:gauge, "Authors whose first op landed inside the window (activation)."},
    "elix_returning_authors" =>
      {:gauge, "Window-active authors whose first op predates it (retention)."}
  }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Increment a counter series (by 1 by default) for the given label set."
  def inc(name, labels \\ %{}, by \\ 1) do
    ensure_table()

    :ets.update_counter(
      @table,
      {:counter, name, normalize(labels)},
      {2, by},
      {{:counter, name, normalize(labels)}, 0}
    )

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Set a gauge series to an absolute value."
  def set(name, labels \\ %{}, value) do
    ensure_table()
    :ets.insert(@table, {{:gauge, name, normalize(labels)}, value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Record a histogram observation (seconds) into bucket + sum + count series."
  def observe(name, labels \\ %{}, value) when is_number(value) do
    ensure_table()
    norm = normalize(labels)

    # Cumulative bucket counters: bump every bucket whose upper bound >= value,
    # plus the +Inf bucket, plus _sum and _count aggregates.
    for le <- @buckets, value <= le do
      :ets.update_counter(
        @table,
        {:hist_bucket, name, norm, le},
        {2, 1},
        {{:hist_bucket, name, norm, le}, 0}
      )
    end

    :ets.update_counter(
      @table,
      {:hist_bucket, name, norm, :inf},
      {2, 1},
      {{:hist_bucket, name, norm, :inf}, 0}
    )

    :ets.update_counter(@table, {:hist_count, name, norm}, {2, 1}, {{:hist_count, name, norm}, 0})

    # Sum is float; store via read-modify-write (rare path, contention is fine).
    key = {:hist_sum, name, norm}

    sum =
      case :ets.lookup(@table, key) do
        [{^key, s}] -> s
        [] -> 0.0
      end

    :ets.insert(@table, {key, sum + value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Time a zero-arg function, recording its duration into a histogram."
  def time(name, labels \\ %{}, fun) do
    start = System.monotonic_time()
    result = fun.()

    elapsed =
      System.convert_time_unit(System.monotonic_time() - start, :native, :nanosecond) / 1.0e9

    observe(name, labels, elapsed)
    result
  end

  @doc "Render the full registry as Prometheus text-exposition format."
  def render do
    ensure_table()
    rows = :ets.tab2list(@table)

    @metric_defs
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map_join("\n", fn {name, {type, help}} ->
      render_metric(name, type, help, rows)
    end)
    |> Kernel.<>("\n")
  end

  # --- GenServer (owns the ETS table + gauge poller) ---

  @impl true
  def init(opts) do
    ensure_table()
    interval = Keyword.get(opts, :poll_interval_ms, poll_interval_ms())

    if interval > 0 do
      Process.send_after(self(), :poll_gauges, interval)
    end

    {:ok, %{interval: interval}}
  end

  # Product-pulse gauges are COUNT DISTINCT scans — sample them every Nth
  # gauge tick (default 15s * 20 = 5min) rather than on every poll.
  @product_pulse_every 20

  @impl true
  def handle_info(:poll_gauges, %{interval: interval} = state) do
    tick = Map.get(state, :tick, 0)
    poll_gauges()

    if rem(tick, @product_pulse_every) == 0 do
      sample_product_pulse()
    end

    if interval > 0, do: Process.send_after(self(), :poll_gauges, interval)
    {:noreply, Map.put(state, :tick, tick + 1)}
  end

  @doc "Sample gauge series. Safe to call directly in tests."
  def poll_gauges do
    set("relay_op_table_rows", %{}, op_table_rows())
    :ok
  rescue
    error ->
      Logger.warning("Metrics.poll_gauges failed: #{inspect(error.__struct__)}")
      :ok
  end

  defp sample_product_pulse do
    AnsibleRelay.ProductPulse.sample()
  rescue
    error ->
      Logger.warning("ProductPulse.sample failed: #{inspect(error.__struct__)}")
      :ok
  end

  # --- Internals ---

  defp op_table_rows do
    AnsibleRelay.Repo.aggregate(AnsibleRelay.Db.Op, :count, :id)
  rescue
    _ -> 0
  end

  defp poll_interval_ms do
    Application.get_env(:ansible_relay, :metrics_poll_interval_ms, @default_poll_interval_ms)
  end

  defp render_metric(name, type, help, rows) do
    header = "# HELP #{name} #{help}\n# TYPE #{name} #{type}"
    body = render_body(name, type, rows)

    case body do
      "" -> header <> "\n#{name} 0"
      _ -> header <> "\n" <> body
    end
  end

  defp render_body(name, :counter, rows) do
    rows
    |> Enum.filter(&match?({{:counter, ^name, _}, _}, &1))
    |> Enum.map_join("\n", fn {{:counter, ^name, labels}, value} ->
      "#{name}#{render_labels(labels)} #{value}"
    end)
  end

  defp render_body(name, :gauge, rows) do
    rows
    |> Enum.filter(&match?({{:gauge, ^name, _}, _}, &1))
    |> Enum.map_join("\n", fn {{:gauge, ^name, labels}, value} ->
      "#{name}#{render_labels(labels)} #{value}"
    end)
  end

  defp render_body(name, :histogram, rows) do
    label_sets =
      rows
      |> Enum.flat_map(fn
        {{:hist_count, ^name, labels}, _} -> [labels]
        _ -> []
      end)
      |> Enum.uniq()

    Enum.map_join(label_sets, "\n", fn labels ->
      buckets =
        Enum.map_join(@buckets ++ [:inf], "\n", fn le ->
          count = lookup_count(rows, {:hist_bucket, name, labels, le})
          le_str = if le == :inf, do: "+Inf", else: to_string(le)
          "#{name}_bucket#{render_labels(Map.put(labels, "le", le_str))} #{count}"
        end)

      sum = lookup_sum(rows, {:hist_sum, name, labels})
      count = lookup_count(rows, {:hist_count, name, labels})

      buckets <>
        "\n#{name}_sum#{render_labels(labels)} #{sum}" <>
        "\n#{name}_count#{render_labels(labels)} #{count}"
    end)
  end

  defp lookup_count(rows, key) do
    case List.keyfind(rows, key, 0) do
      {^key, v} -> v
      _ -> 0
    end
  end

  defp lookup_sum(rows, key) do
    case List.keyfind(rows, key, 0) do
      {^key, v} -> v
      _ -> 0
    end
  end

  defp render_labels(labels) when labels == %{}, do: ""

  defp render_labels(labels) do
    inner =
      labels
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join(",", fn {k, v} -> "#{k}=\"#{escape(to_string(v))}\"" end)

    "{" <> inner <> "}"
  end

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp normalize(labels) when is_map(labels) do
    Map.new(labels, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _tid ->
        @table
    end
  rescue
    ArgumentError -> @table
  end
end
