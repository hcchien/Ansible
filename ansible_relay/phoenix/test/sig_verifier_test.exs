defmodule AnsibleRelay.SigVerifierTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.SigVerifier

  test "verifies real Ed25519 signatures" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    message = "registration-nonce"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])

    assert SigVerifier.verify_ed25519(
             Base.encode16(public_key, case: :lower),
             message,
             Base.encode16(signature, case: :lower)
           )
  end

  test "rejects development stub signatures" do
    {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519)

    refute SigVerifier.verify_ed25519(
             Base.encode16(public_key, case: :lower),
             "registration-nonce",
             "dev-sig-cmVnaXN0cmF0aW9uLW5vbmNl"
           )
  end

  test "verifies BIP-340 Schnorr signatures for Nostr pubkeys" do
    assert SigVerifier.verify_schnorr_bip340(
             "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
             "0000000000000000000000000000000000000000000000000000000000000000",
             "e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215" <>
               "25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0"
           )
  end
end
