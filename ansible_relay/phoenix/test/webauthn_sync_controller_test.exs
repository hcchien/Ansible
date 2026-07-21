defmodule AnsibleRelay.Web.WebauthnSyncControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{Db.WebauthnChallenge, IdentityCache, Repo}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case IdentityCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "verified DID receives persistent passkey registration options" do
    did = "did:key:z6MkWebauthn#{System.unique_integer([:positive])}"
    IdentityCache.put(did, String.duplicate("ab", 32), "nullifier-#{did}")

    response =
      post_json("/api/v2/webauthn/register/options", %{
        "did" => did
      })

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["publicKey"]["rp"]["id"] == "elix.cool"
    assert body["publicKey"]["userVerification"] == nil
    assert body["publicKey"]["authenticatorSelection"]["userVerification"] == "required"
    assert body["publicKey"]["challenge"] != ""

    challenge = Repo.get!(WebauthnChallenge, body["challenge_id"])
    assert challenge.did == did
    assert challenge.kind == "registration"
    assert challenge.consumed_at == nil
  end

  test "unverified DID cannot start passkey enrollment" do
    response =
      post_json("/api/v2/webauthn/register/options", %{
        "did" => "did:key:z6MkUnknown"
      })

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "unverified_did"
  end

  test "authentication options require an enrolled credential" do
    did = "did:key:z6MkNoCredential#{System.unique_integer([:positive])}"
    IdentityCache.put(did, String.duplicate("cd", 32), "nullifier-#{did}")

    response =
      post_json("/api/v2/webauthn/authenticate/options", %{
        "did" => did,
        "scope" => "sync:write"
      })

    assert response.status == 409
    assert Jason.decode!(response.resp_body)["error"] == "passkey_not_enrolled"
  end

  test "authentication options reject scope escalation" do
    did = "did:key:z6MkScope#{System.unique_integer([:positive])}"
    IdentityCache.put(did, String.duplicate("ef", 32), "nullifier-#{did}")

    response =
      post_json("/api/v2/webauthn/authenticate/options", %{
        "did" => did,
        "scope" => "admin"
      })

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_scope"
  end
end
