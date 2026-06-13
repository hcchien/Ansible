defmodule AnsibleRelay.MetricsTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{AbuseDetector, IdentityCache, Metrics, OpStore}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    for mod <- [IdentityCache, AbuseDetector, OpStore, AnsibleRelay.DidAccountCache, Metrics] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    AbuseDetector.reset()
    :ok
  end

  test "GET /metrics returns 200 Prometheus text with the declared series" do
    conn = conn(:get, "/metrics") |> Router.call(@router_opts)

    assert conn.status == 200

    assert Enum.any?(conn.resp_headers, fn {k, v} ->
             k == "content-type" and String.starts_with?(v, "text/plain; version=0.0.4")
           end)

    body = conn.resp_body
    assert body =~ "# TYPE relay_op_ingest_total counter"
    assert body =~ "# TYPE relay_op_table_rows gauge"
    assert body =~ "# TYPE relay_signature_verifications_total counter"
    assert body =~ "# TYPE relay_delta_request_duration_seconds histogram"
  end

  test "ingesting an op surfaces the ingest and signature counters at /metrics" do
    did = "did:key:z6MkMetrics#{System.unique_integer()}"
    {public_key, private_key} = ed25519_keypair()
    IdentityCache.put(did, public_key, "nullifier_#{System.unique_integer()}")

    response = post_json("/api/v1/ops", valid_op(did, private_key))
    assert response.status == 202

    body = conn(:get, "/metrics") |> Router.call(@router_opts) |> Map.fetch!(:resp_body)

    assert body =~ ~r/relay_op_ingest_total\{entity_type="post",op_type="insert"\} [1-9]/
    assert body =~ ~r/relay_signature_verifications_total\{result="pass"\} [1-9]/
  end

  test "poll_gauges reports the ops table row count" do
    assert Metrics.poll_gauges() == :ok
    body = Metrics.render()
    assert body =~ ~r/relay_op_table_rows \d+/
  end

  # --- helpers (mirror ops_controller_test) ---

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp valid_op(did, private_key) do
    op = %{
      "op_id" => "op-#{System.unique_integer()}",
      "author_did" => did,
      "entity_type" => "post",
      "entity_id" => "entity-#{System.unique_integer()}",
      "op_type" => "insert",
      "payload" => Base.encode64("hello world")
    }

    Map.put(op, "signature", sign(private_key, signing_payload(op)))
  end

  defp signing_payload(op) do
    %{
      "author_did" => op["author_did"],
      "entity_id" => op["entity_id"],
      "entity_type" => op["entity_type"],
      "op_id" => op["op_id"],
      "op_type" => op["op_type"],
      "payload" => op["payload"]
    }
    |> canonical_json()
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)
end
