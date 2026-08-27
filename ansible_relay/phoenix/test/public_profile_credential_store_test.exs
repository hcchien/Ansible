defmodule AnsibleRelay.PublicProfileCredentialStoreTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Identity.PublicProfileCredentialStore

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})
    :ok
  end

  test "stores only a minimal age badge and never the VC or credential id" do
    did = "did:elix:profileholder"

    vc = %{
      "id" => "urn:uuid:secret-credential-id",
      "type" => ["VerifiableCredential", "AgeOver18Credential"],
      "issuer" => "did:web:issuer.elix.cool",
      "validUntil" => "2027-08-27T00:00:00Z",
      "credentialSubject" => %{
        "id" => did,
        "ageOver18" => true,
        "birthDate" => "1990-01-01"
      },
      "proof" => %{"proofValue" => "secret-proof"}
    }

    assert {:ok, public} =
             PublicProfileCredentialStore.put_verified(did, "AgeOver18Credential", vc)

    assert public.badge == "age_over_18"
    assert public.value == "true"
    refute inspect(public) =~ "secret-credential-id"
    refute inspect(public) =~ "1990-01-01"
    refute inspect(public) =~ "secret-proof"

    assert [listed] =
             PublicProfileCredentialStore.list_public(did, ["AgeOver18Credential"])

    assert listed == public
    assert PublicProfileCredentialStore.list_public(did, []) == []
  end

  test "rejects email and false age claims" do
    base = %{
      "issuer" => "did:web:issuer.elix.cool",
      "validUntil" => "2027-08-27T00:00:00Z",
      "credentialSubject" => %{"id" => "did:elix:holder", "ageOver18" => false}
    }

    assert {:error, :unsupported_credential_type} =
             PublicProfileCredentialStore.put_verified(
               "did:elix:holder",
               "EmailCredential",
               base
             )

    assert {:error, :invalid_public_profile_claim} =
             PublicProfileCredentialStore.put_verified(
               "did:elix:holder",
               "AgeOver18Credential",
               base
             )
  end
end
