defmodule AnsibleRelay.Identity.HandleVerifierTest do
  @moduledoc """
  DNS handle verification (Phase 4.3) — resolver-injected unit tests plus
  the endpoint's parameter validation (never triggers real lookups).
  """

  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Identity.HandleVerifier
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])
  @did "did:elix:abcdefghijklmnop"

  setup do
    case AnsibleRelay.AbuseDetector.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    AnsibleRelay.AbuseDetector.reset()
    :ok
  end

  defp dns(records), do: fn _name -> {:ok, records} end
  defp dns_error, do: fn _name -> {:error, :no_records} end
  defp http(body), do: fn _handle -> {:ok, [body]} end
  defp http_error, do: fn _handle -> {:error, :unreachable} end

  test "DNS TXT did= record verifies" do
    assert {:ok, :dns} =
             HandleVerifier.verify("alice.example.com", @did,
               dns_txt_resolver: dns(["did=#{@did}"]),
               well_known_resolver: http_error()
             )
  end

  test "well-known body verifies when DNS has no record" do
    assert {:ok, :well_known} =
             HandleVerifier.verify("alice.example.com", @did,
               dns_txt_resolver: dns_error(),
               well_known_resolver: http("#{@did}\n")
             )
  end

  test "a TXT record for a DIFFERENT did does not verify" do
    assert {:error, :not_verified} =
             HandleVerifier.verify("alice.example.com", @did,
               dns_txt_resolver: dns(["did=did:elix:someoneelse"]),
               well_known_resolver: http_error()
             )
  end

  test "no proof anywhere → not_verified" do
    assert {:error, :not_verified} =
             HandleVerifier.verify("alice.example.com", @did,
               dns_txt_resolver: dns_error(),
               well_known_resolver: http_error()
             )
  end

  test "malformed handles are rejected before any lookup" do
    boom = fn _name -> flunk("resolver must not run for invalid handles") end

    for bad <- [
          "https://alice.example.com",
          "alice.example.com/path",
          "alice",
          "alice..example.com",
          "-alice.example.com",
          ""
        ] do
      assert {:error, :invalid_handle} =
               HandleVerifier.verify(bad, @did,
                 dns_txt_resolver: boom,
                 well_known_resolver: boom
               )
    end
  end

  test "endpoint validates params without triggering lookups" do
    response =
      conn(:get, "/api/v1/identity/verify-handle?handle=&did=#{@did}")
      |> Router.call(@router_opts)

    assert response.status == 422

    response =
      conn(:get, "/api/v1/identity/verify-handle?handle=not..a..host&did=#{@did}")
      |> Router.call(@router_opts)

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_handle"
  end
end
