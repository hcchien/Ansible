defmodule AnsibleAppview.MetricsTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleAppview.Ingest.Folder
  alias AnsibleAppview.{Metrics, SigningPayload}
  alias AnsibleAppview.Web.Router

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleAppview.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleAppview.Repo, {:shared, self()})

    case Metrics.start_link(poll_interval_ms: 0) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "GET /metrics returns 200 Prometheus text with the declared series" do
    conn = conn(:get, "/metrics") |> Router.call(@router_opts)

    assert conn.status == 200

    assert Enum.any?(conn.resp_headers, fn {k, v} ->
             k == "content-type" and String.starts_with?(v, "text/plain; version=0.0.4")
           end)

    body = conn.resp_body
    assert body =~ "# TYPE appview_ingest_folds_total counter"
    assert body =~ "# TYPE appview_ingest_lag_seconds gauge"
    assert body =~ "# TYPE appview_timeline_requests_total counter"
    assert body =~ "# TYPE appview_timeline_request_duration_seconds histogram"
  end

  test "folding ops surfaces the ingest fold counter at /metrics" do
    {pub, priv} = keypair()

    ops = [
      signed_op(
        log_id: 1,
        author_did: "did:key:alice",
        entity_type: "murmur",
        pub: pub,
        priv: priv,
        payload: %{"mode" => "murmur", "body" => "hello", "visibility" => "public"}
      )
    ]

    {indexed, _max_log} = Folder.apply_ops(ops)
    assert indexed == 1

    body = conn(:get, "/metrics") |> Router.call(@router_opts) |> Map.fetch!(:resp_body)
    assert body =~ ~r/appview_ingest_folds_total [1-9]/
  end

  test "poll_gauges reports an ingest lag gauge" do
    assert Metrics.poll_gauges() == :ok
    body = Metrics.render()
    assert body =~ ~r/appview_ingest_lag_seconds \d+/
  end

  # --- helpers (mirror ingest_timeline_test) ---

  defp keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp signed_op(opts) do
    priv = Keyword.fetch!(opts, :priv)

    op = %{
      "log_id" => Keyword.fetch!(opts, :log_id),
      "op_id" => Keyword.get(opts, :op_id, "op-#{Keyword.fetch!(opts, :log_id)}"),
      "author_did" => Keyword.fetch!(opts, :author_did),
      "entity_type" => Keyword.fetch!(opts, :entity_type),
      "entity_id" => Keyword.get(opts, :entity_id, "e-#{Keyword.fetch!(opts, :log_id)}"),
      "op_type" => Keyword.get(opts, :op_type, "insert"),
      "payload" => Base.encode64(Jason.encode!(Keyword.get(opts, :payload, %{}))),
      "public_key_hex" => Keyword.fetch!(opts, :pub),
      "reputation_tier" => Keyword.get(opts, :reputation_tier, "basic"),
      "received_at" => "2026-06-05T00:00:00Z"
    }

    signature =
      :crypto.sign(:eddsa, :none, SigningPayload.build(op), [priv, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(op, "signature", signature)
  end
end
