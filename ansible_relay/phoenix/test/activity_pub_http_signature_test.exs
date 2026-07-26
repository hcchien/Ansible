defmodule AnsibleRelay.ActivityPub.HttpSignatureTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.ActivityPub.HttpSignature

  test "fails closed when the transport signing key is absent" do
    assert {:error, :activity_pub_signing_key_missing} =
             HttpSignature.headers(
               :post,
               "https://remote.example/inbox",
               ~s({"type":"Create"}),
               "https://relay.elix.cool/users/alice",
               private_key_pem: nil
             )
  end

  test "signs the ActivityPub delivery headers with RSA-SHA256" do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})

    pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
      ])

    assert {:ok, headers} =
             HttpSignature.headers(
               :post,
               "https://remote.example/inbox",
               ~s({"type":"Create"}),
               "https://relay.elix.cool/users/alice",
               private_key_pem: pem
             )

    assert {~c"digest", digest} = List.keyfind(headers, ~c"digest", 0)
    assert List.to_string(digest) =~ "SHA-256="
    assert {~c"signature", signature} = List.keyfind(headers, ~c"signature", 0)
    assert List.to_string(signature) =~ ~s(keyId="https://relay.elix.cool/users/alice#main-key")
  end
end
