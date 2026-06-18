defmodule AnsibleRelay.Web.IdentityControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  # The Phase 1 ZKP challenge/anchor flow was retired (did:elix + the
  # self-certifying anchor replaced it). Only the public-key read survives.

  alias AnsibleRelay.IdentityCache
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp get_req(path) do
    conn(:get, path)
    |> Router.call(@router_opts)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    case IdentityCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "public-key returns the verified key hex for a registered DID" do
    did = "did:elix:pubkey#{System.unique_integer([:positive])}"
    :ok = IdentityCache.put(did, "abcdef0123456789")

    response = get_req("/api/v1/identity/public-key/#{did}")

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["did"] == did
    assert body["public_key_hex"] == "abcdef0123456789"
  end

  test "public-key returns 404 for an unknown DID" do
    response = get_req("/api/v1/identity/public-key/did:elix:unknown")

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "did_not_found"
  end

  test "handle returns the registered handle for a DID" do
    case AnsibleRelay.DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    did = "did:plc:handle#{System.unique_integer([:positive])}"
    handle = "alice#{System.unique_integer([:positive])}.elix.cool"
    :ok = AnsibleRelay.DidAccountCache.put(did, "abcdef0123456789", handle)

    response = get_req("/api/v1/identity/handle/#{did}")

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["did"] == did
    assert body["handle"] == handle
  end

  test "handle returns 404 for an unknown DID" do
    response = get_req("/api/v1/identity/handle/did:plc:nohandle")

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "handle_not_found"
  end
end
