defmodule AnsibleRelay.Web.ProtocolVersionTest do
  @moduledoc """
  Phase 0 — API versioning: meta advertisement and the `x-ansible-protocol`
  enforcement plug (`AnsibleRelay.Web.Plugs.RequireProtocolVersion`).
  """

  use ExUnit.Case, async: true
  use Plug.Test

  alias AnsibleRelay.Protocol
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp get_meta(headers \\ []) do
    Enum.reduce(headers, conn(:get, "/api/v1/meta"), fn {name, value}, conn ->
      put_req_header(conn, name, value)
    end)
    |> Router.call(@router_opts)
  end

  # ---- GET /api/v1/meta ----

  test "meta advertises service and protocol versions" do
    response = get_meta()
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["service"] == "ansible_relay"

    assert body["protocol"] == %{
             "current" => Protocol.current_version(),
             "min_supported" => Protocol.min_supported_version()
           }
  end

  # ---- RequireProtocolVersion plug ----

  test "request without the protocol header is allowed (legacy grace)" do
    assert get_meta().status == 200
  end

  test "request at the current protocol version is allowed" do
    response = get_meta([{Protocol.header(), "#{Protocol.current_version()}"}])
    assert response.status == 200
  end

  test "request from a newer client is allowed (forward-compatible)" do
    response = get_meta([{Protocol.header(), "#{Protocol.current_version() + 5}"}])
    assert response.status == 200
  end

  test "request below min supported version gets 426 upgrade_required" do
    response = get_meta([{Protocol.header(), "#{Protocol.min_supported_version() - 1}"}])
    assert response.status == 426

    body = Jason.decode!(response.resp_body)
    assert body["error"] == "upgrade_required"
    assert body["min_supported"] == Protocol.min_supported_version()
    assert body["current"] == Protocol.current_version()
  end

  test "unparseable protocol header is allowed like a legacy client" do
    response = get_meta([{Protocol.header(), "not-a-number"}])
    assert response.status == 200
  end

  test "non-API routes are never gated by the protocol header" do
    response =
      conn(:get, "/health")
      |> put_req_header(Protocol.header(), "0")
      |> Router.call(@router_opts)

    assert response.status == 200
  end
end
