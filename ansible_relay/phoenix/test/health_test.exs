defmodule AnsibleRelay.Web.HealthTest do
  @moduledoc "Liveness (/health) and readiness (/readyz) endpoints."

  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{Repo}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp get(path) do
    conn(:get, path) |> Router.call(@router_opts)
  end

  test "/health is cheap and always ok (no DB touch)" do
    response = get("/health")
    assert response.status == 200
    assert Jason.decode!(response.resp_body)["status"] == "ok"
  end

  test "/readyz pings the database and reports ready" do
    response = get("/readyz")
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["status"] == "ready"
  end
end
