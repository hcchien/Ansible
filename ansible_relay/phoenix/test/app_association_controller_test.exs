defmodule AnsibleRelay.Web.AppAssociationControllerTest do
  @moduledoc """
  OS universal-link association files: fail-closed 404 until configured, then
  well-formed AASA / assetlinks documents scoped to /boards/* content links.
  """

  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  @ios_var "UNIVERSAL_LINK_IOS_APP_IDS"
  @android_package_var "APP_LINK_ANDROID_PACKAGE"
  @android_certs_var "APP_LINK_ANDROID_SHA256_CERTS"

  # No DB setup: these routes read only environment variables.
  setup do
    for var <- [@ios_var, @android_package_var, @android_certs_var] do
      System.delete_env(var)
    end

    on_exit(fn ->
      for var <- [@ios_var, @android_package_var, @android_certs_var] do
        System.delete_env(var)
      end
    end)

    :ok
  end

  defp get(path) do
    conn(:get, path) |> Router.call(@router_opts)
  end

  test "AASA 404s when unconfigured (fail-closed)" do
    for path <- ["/.well-known/apple-app-site-association", "/apple-app-site-association"] do
      response = get(path)
      assert response.status == 404
      assert Jason.decode!(response.resp_body)["error"] == "universal_links_not_configured"
    end
  end

  test "assetlinks 404s when unconfigured (fail-closed)" do
    response = get("/.well-known/assetlinks.json")
    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "app_links_not_configured"
  end

  test "assetlinks 404s when only one of package/certs is set" do
    System.put_env(@android_package_var, "io.trisaura.ansible_node")
    assert get("/.well-known/assetlinks.json").status == 404

    System.delete_env(@android_package_var)
    System.put_env(@android_certs_var, "AA:BB")
    assert get("/.well-known/assetlinks.json").status == 404
  end

  test "AASA serves the configured appIDs scoped to /boards/*" do
    System.put_env(@ios_var, "T68YYD5V2Y.com.example.ansibleNode, T68YYD5V2Y.cool.elix.app")

    for path <- ["/.well-known/apple-app-site-association", "/apple-app-site-association"] do
      response = get(path)
      assert response.status == 200
      assert response.resp_headers |> Map.new() |> Map.get("content-type") =~ "application/json"

      %{"applinks" => %{"details" => [detail]}} = Jason.decode!(response.resp_body)
      assert detail["appIDs"] == ["T68YYD5V2Y.com.example.ansibleNode", "T68YYD5V2Y.cool.elix.app"]
      assert detail["components"] == [%{"/" => "/boards/*"}]
      assert detail["paths"] == ["/boards/*"]
    end
  end

  test "assetlinks serves the configured package + fingerprints" do
    System.put_env(@android_package_var, "io.trisaura.ansible_node")

    System.put_env(
      @android_certs_var,
      "04:EE:D4:93:7A:9B:12:8F:C8:3C:3F:86:6D:9D:92:91:C1:0F:AF:05:4B:5A:E2:C1:EC:B4:74:36:78:1E:6B:F0"
    )

    response = get("/.well-known/assetlinks.json")
    assert response.status == 200

    [statement] = Jason.decode!(response.resp_body)
    assert statement["relation"] == ["delegate_permission/common.handle_all_urls"]
    assert statement["target"]["namespace"] == "android_app"
    assert statement["target"]["package_name"] == "io.trisaura.ansible_node"
    assert [fingerprint] = statement["target"]["sha256_cert_fingerprints"]
    assert String.starts_with?(fingerprint, "04:EE:D4:")
  end
end
