defmodule AnsibleRelay.PublicAuthorityStatusTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.{
    Repo,
    Db.WebauthnCredential,
    Authority.PublicStatus,
    IdentityCache,
    WebauthnSync
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    did = "did:elix:status-test"
    IdentityCache.put(did, Base.encode16(public, case: :lower), "status-test-nullifier")

    credential =
      Repo.insert!(%WebauthnCredential{
        credential_id: "test-credential",
        did: did,
        cose_key: <<1>>,
        transports: ["internal"]
      })

    payload = %{
      "web_author_proof" => %{
        "credential_id" => Base.url_encode64(credential.credential_id, padding: false)
      }
    }

    op = %{author_did: did, payload: Base.encode64(Jason.encode!(payload))}
    %{did: did, private: private, credential: credential, op: op}
  end

  test "public status exposes only the credential referenced by the public operation", c do
    status = PublicStatus.for_operation(c.op, [%{"public" => "chain"}])

    assert %{version: 1, state: "active", credential: %{state: "active", revoked_at: nil}} =
             status

    assert Map.keys(status.credential) |> Enum.sort() == [:credential_hash, :revoked_at, :state]
    refute Jason.encode!(status) =~ "test-credential"
    refute Jason.encode!(status) =~ "transports"

    assert PublicStatus.for_operation(%{c.op | payload: Base.encode64("{}")}, [%{}]).credential ==
             nil

    assert PublicStatus.for_operation(c.op, []).state == "unavailable"
  end

  test "credential ownership mismatch fails closed", c do
    status = PublicStatus.for_operation(%{c.op | author_did: "did:elix:someone-else"}, [%{}])
    assert status.credential.state == "unknown"
  end

  test "revocation retry preserves its earliest effective time", c do
    at = DateTime.add(DateTime.utc_now(), -60)

    revoke = fn timestamp ->
      body = %{
        "type" => "io.trisaura.identity.webCredentialRevocation",
        "version" => 1,
        "subject_did" => c.did,
        "credential_id" => Base.url_encode64(c.credential.credential_id, padding: false),
        "nonce" => "revocation-retry-nonce",
        "revoked_at" => DateTime.to_iso8601(timestamp)
      }

      bytes =
        "{" <>
          (body
           |> Enum.sort_by(&elem(&1, 0))
           |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> Jason.encode!(v) end)) <>
          "}"

      signature =
        :crypto.sign(:eddsa, :none, bytes, [c.private, :ed25519]) |> Base.encode16(case: :lower)

      WebauthnSync.revoke_credential(c.did, body["credential_id"], body, signature)
    end

    assert {:ok, _} = revoke.(at)
    assert {:ok, _} = revoke.(DateTime.add(at, 30))

    assert %{credential: %{state: "revoked", revoked_at: result}} =
             PublicStatus.for_operation(c.op, [%{}])

    assert result == DateTime.to_iso8601(at)
  end
end
