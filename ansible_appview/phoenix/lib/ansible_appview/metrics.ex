defmodule AnsibleAppview.Metrics do
  @moduledoc """
  Observability baseline (service architecture plan, Phase 0 — closes G17).

  A dependency-free Prometheus metrics registry: counters, gauges, and
  histograms live in a public ETS table owned by this GenServer, instrumentation
  points call `inc/2`, `set/2`, and `observe/3` directly, and `render/0`
  produces Prometheus text-format output served at `GET /metrics`.

  The GenServer also runs a periodic poller for the ingest-lag gauge — the wall
  clock distance between now and the newest folded op — which Phase 3's exit
  criteria measure.

  Concurrency: counter/histogram updates use `:ets.update_counter/4` (atomic,
  lock-free) against a `:public` table with write concurrency.

  ## Exposed series (appview)

    * `appview_ingest_folds_total` — ops folded into the projection
    * `appview_ingest_lag_seconds` (gauge) — now − newest folded op timestamp
    * `appview_timeline_requests_total{kind}` — timeline reads (following/home/board)
    * `appview_timeline_request_duration_seconds` (histogram) — timeline latency
    * `appview_discovery_requests_total{kind}` — discovery/explore/search reads
    * `appview_discovery_request_duration_seconds` (histogram) — discovery latency
  """

  use GenServer
  require Logger

  @table :ansible_appview_metrics
  @buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
  @default_poll_interval_ms 15_000

  @metric_defs %{
    "appview_ingest_folds_total" => {:counter, "Ops folded into the feed projection."},
    "appview_ingest_lag_seconds" =>
      {:gauge, "Seconds between now and the newest folded op timestamp."},
    "appview_timeline_requests_total" =>
      {:counter, "Timeline read requests by kind (following/home/board)."},
    "appview_timeline_request_duration_seconds" =>
      {:histogram, "Timeline read request latency in seconds."},
    "appview_discovery_requests_total" =>
      {:counter, "Discovery read requests by kind (explore/suggest/search)."},
    "appview_discovery_request_duration_seconds" =>
      {:histogram, "Discovery read request latency in seconds."}
  }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def inc(name, labels \\ %{}, by \\ 1) do
    ensure_table()
    key = {:counter, name, normalize(labels)}
    :ets.update_counter(@table, key, {2, by}, {key, 0})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def set(name, labels \\ %{}, value) do
    ensure_table()
    :ets.insert(@table, {{:gauge, name, normalize(labels)}, value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def observe(name, labels \\ %{}, value) when is_number(value) do
    ensure_table()
    norm = normalize(labels)

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

  def time(name, labels \\ %{}, fun) do
    start = System.monotonic_time()
    result = fun.()

    elapsed =
      System.convert_time_unit(System.monotonic_time() - start, :native, :nanosecond) / 1.0e9

    observe(name, labels, elapsed)
    result
  end

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

  @impl true
  def handle_info(:poll_gauges, %{interval: interval} = state) do
    poll_gauges()
    if interval > 0, do: Process.send_after(self(), :poll_gauges, interval)
    {:noreply, state}
  end

  @doc "Sample gauge series. Safe to call directly in tests."
  def poll_gauges do
    set("appview_ingest_lag_seconds", %{}, ingest_lag_seconds())
    :ok
  rescue
    error ->
      Logger.warning("Metrics.poll_gauges failed: #{inspect(error.__struct__)}")
      :ok
  end

  # --- Internals ---

  # Lag = now − newest folded op's content timestamp. Zero when the projection
  # is empty (nothing to be behind on).
  defp ingest_lag_seconds do
    import Ecto.Query

    latest =
      AnsibleAppview.Repo.one(
        from(f in AnsibleAppview.Db.FeedItem, select: max(f.item_created_at))
      )

    case latest do
      %DateTime{} = dt -> max(DateTime.diff(DateTime.utc_now(), dt, :second), 0)
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp poll_interval_ms do
    Application.get_env(:ansible_appview, :metrics_poll_interval_ms, @default_poll_interval_ms)
  end

  defp render_metric(name, type, help, rows) do
    header = "# HELP #{name} #{help}\n# TYPE #{name} #{type}"
    body = render_body(name, type, rows)

    case body do
      "" -> header <> "\n#{name} 0"
      _ -> header <> "\n" <> body
    end
  end

  defp render_body(name, kind, rows) when kind in [:counter, :gauge] do
    rows
    |> Enum.filter(&match?({{^kind, ^name, _}, _}, &1))
    |> Enum.map_join("\n", fn {{^kind, ^name, labels}, value} ->
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
          count = lookup(rows, {:hist_bucket, name, labels, le})
          le_str = if le == :inf, do: "+Inf", else: to_string(le)
          "#{name}_bucket#{render_labels(Map.put(labels, "le", le_str))} #{count}"
        end)

      sum = lookup(rows, {:hist_sum, name, labels})
      count = lookup(rows, {:hist_count, name, labels})

      buckets <>
        "\n#{name}_sum#{render_labels(labels)} #{sum}" <>
        "\n#{name}_count#{render_labels(labels)} #{count}"
    end)
  end

  defp lookup(rows, key) do
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
