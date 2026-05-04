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
end
