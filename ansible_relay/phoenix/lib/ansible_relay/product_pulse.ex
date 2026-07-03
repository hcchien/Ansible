defmodule AnsibleRelay.ProductPulse do
  @moduledoc """
  Constitutional product measurement (PM review P1; design doc
  `docs/superpowers/specs/2026-07-03-constitutional-measurement-design.md`).

  Aggregate-only activation/retention/board-activity gauges computed
  server-side from data the relay already holds for its core function (the
  op log and DID accounts) and exposed on the existing Prometheus
  `/metrics` endpoint. Constitution boundaries enforced by construction:

    * No new data collection — every series is a `COUNT(...)` over existing
      rows; nothing per-user is stored, emitted, or labeled.
    * No client-side analytics/telemetry — the app sends nothing.
    * Coarse windows (1d/7d/28d) only; no cohorts smaller than the whole
      relay population, no per-DID or per-board output.

  Sampled by the Metrics poller on a slow cadence — these are COUNT DISTINCT
  scans, priced accordingly.
  """

  import Ecto.Query

  alias AnsibleRelay.{Db.DidAccount, Db.Op, Metrics, Repo}

  @windows [{"1d", 1}, {"7d", 7}, {"28d", 28}]

  @doc "Sample every product-pulse gauge. Safe to call directly in tests."
  def sample do
    now = DateTime.utc_now()

    Metrics.set("elix_registered_dids", %{}, count(from(d in DidAccount)))

    for {label, days} <- @windows do
      since = DateTime.add(now, -days * 86_400, :second)

      Metrics.set(
        "elix_active_authors",
        %{window: label},
        count(
          from(o in Op,
            where: o.received_at >= ^since,
            select: o.author_did,
            distinct: true
          )
        )
      )

      active_boards =
        from(o in Op,
          where:
            o.received_at >= ^since and o.entity_type in ["thread", "post"] and
              fragment("COALESCE(?::jsonb ->> 'boardId', '') <> ''", o.payload),
          select: %{board_id: fragment("(?::jsonb ->> 'boardId')", o.payload)},
          distinct: true
        )

      Metrics.set(
        "elix_active_boards",
        %{window: label},
        count(from(b in subquery(active_boards)))
      )
    end

    week_ago = DateTime.add(now, -7 * 86_400, :second)

    # Activation: authors whose FIRST op landed inside the last 7 days.
    # Retention proxy: authors active in the last 7 days whose first op is
    # older — they came back. Both are single aggregate counts.
    first_ops =
      from(o in Op,
        group_by: o.author_did,
        select: %{author_did: o.author_did, first_at: min(o.received_at)}
      )

    active_dids =
      from(o in Op,
        where: o.received_at >= ^week_ago,
        select: o.author_did,
        distinct: true
      )

    Metrics.set(
      "elix_new_authors",
      %{window: "7d"},
      count(from(f in subquery(first_ops), where: f.first_at >= ^week_ago))
    )

    Metrics.set(
      "elix_returning_authors",
      %{window: "7d"},
      count(
        from(f in subquery(first_ops),
          where: f.first_at < ^week_ago and f.author_did in subquery(active_dids)
        )
      )
    )

    :ok
  end

  defp count(query) do
    Repo.aggregate(query, :count)
  rescue
    _ -> 0
  end
end
