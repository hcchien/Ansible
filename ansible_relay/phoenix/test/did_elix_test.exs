defmodule AnsibleRelay.DidElixTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.DidElix

  # Cross-language vectors generated from the Dart `deriveDidElix`
  # (ansible_core/store) — these MUST match byte-for-byte so an anchor minted
  # by the app self-certifies on the relay.
  test "derive matches the Dart vectors byte-for-byte" do
    assert DidElix.derive(String.duplicate("aa", 32), "alice.elix.cool") ==
             "did:elix:nxdvwwzy2n6zokf7lhepbvgdl4"

    assert DidElix.derive(
             "b97c30de767f084ce3080168ee293053ba33b235d7116a3263d29f1450936b71",
             "bob.elix.cool"
           ) ==
             "did:elix:w7paqjxbehs6ukzuj72t2uvzau"
  end

  test "matches?/3 self-certifies a canonical did:elix" do
    key = String.duplicate("aa", 32)
    did = DidElix.derive(key, "alice.elix.cool")
    assert DidElix.matches?(did, key, "alice.elix.cool")
    refute DidElix.matches?(did, key, "mallory.elix.cool")
    refute DidElix.matches?(did, String.duplicate("bb", 32), "alice.elix.cool")
    refute DidElix.matches?("did:elix:forged", key, "alice.elix.cool")
  end

  test "v1 derivation and registration payload match the Dart vectors exactly" do
    key = String.duplicate("aa", 32)
    nonce = String.duplicate("01", 32)

    commitment = %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => key,
      "genesis_nonce" => nonce
    }

    expected = "did:elix:zlg5xyogxphkrhi453x3gxpubfxdveaev6xmgnpcw3zus4653mfyq"
    assert DidElix.derive_v1(commitment) == {:ok, expected}
    assert DidElix.matches_v1?(expected, commitment)

    assert DidElix.registration_payload("relay-nonce", expected, commitment) ==
             ~s({"type":"io.trisaura.identity.registration","version":1,"nonce":"relay-nonce","did":"#{expected}","genesis_commitment":{"method":"did:elix","method_version":1,"genesis_key":"#{key}","genesis_nonce":"#{nonce}"}})
  end

  test "v1 commitment rejects uppercase, short, and extended values" do
    base = %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => String.duplicate("aa", 32),
      "genesis_nonce" => String.duplicate("01", 32)
    }

    assert {:error, :invalid_genesis_commitment} =
             DidElix.validate_v1_commitment(%{
               base
               | "genesis_nonce" => String.duplicate("AA", 32)
             })

    assert {:error, :invalid_genesis_commitment} =
             DidElix.validate_v1_commitment(Map.put(base, "unexpected", true))
  end

  test "Ed25519 multibase projection matches the Dart did:key vector" do
    public_key = "b97c30de767f084ce3080168ee293053ba33b235d7116a3263d29f1450936b71"

    assert DidElix.ed25519_multibase(public_key) ==
             {:ok, "z6MkrwKJd14cfGia7TAWXgAZs7GKyXRhPQqTLnkfiG9YY8VN"}

    assert DidElix.ed25519_multibase("00") == {:error, :invalid_public_key}
  end
end
