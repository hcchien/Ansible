defmodule AnsibleAppview.ErrorReporter do
  @moduledoc """
  Central seam for reporting real error conditions.

  The AppView deliberately ships **no** third-party error-reporting SaaS SDK and
  invents no DSN. Instead, error conditions are surfaced two ways that are
  already part of the stack:

    1. **Structured error logs.** `report/2` logs at `:error` with the supplied
       context so operators (and any log-based alerting) see the failure with
       enough to act on it.
    2. **Prometheus metrics.** Aggregate error signals are already exported at
       `GET /metrics` — e.g. `appview_ingest_rejections_total{reason}` (includes
       `reason="poison_op"` dead-letters) and the
       `appview_ingest_drain_consecutive_failures` "drain stuck" gauge. Alerting
       should be built on these series rather than on a per-event SaaS pipeline.

  ## TODO — error-reporting integration seam

  If/when a real error-reporting backend is adopted, wire it in HERE (a single
  `report/2` body) rather than scattering SDK calls across the codebase. Keep the
  two mechanisms above (they are the source of truth for alerting); a backend is
  purely additive. Do not add a DSN or SDK dependency without an explicit
  operational decision.
  """

  require Logger

  @doc """
  Report an error condition. `context` is any term describing where/what
  (keyword list or map preferred). Always logs at `:error`; returns `:ok`.
  """
  @spec report(term(), keyword() | map()) :: :ok
  def report(error, context \\ []) do
    Logger.error("AppView error: #{inspect(error)} context=#{inspect(context)}")
    # TODO(error-reporting seam): forward to a real backend here if one is
    # adopted. Until then, /metrics + these error logs are the alerting surface.
    :ok
  end
end
