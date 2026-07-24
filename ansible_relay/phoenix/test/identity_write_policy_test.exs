defmodule AnsibleRelay.IdentityWritePolicyTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.IdentityWritePolicy

  setup do
    original = Application.get_env(:ansible_relay, :identity_write_algorithms)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :identity_write_algorithms, original)
    end)

    :ok
  end

  test "production policy accepts P-256 writes and rejects Ed25519 writes" do
    Application.put_env(:ansible_relay, :identity_write_algorithms, ["p256-sha256"])

    assert :ok = IdentityWritePolicy.validate("p256-sha256")

    assert {:error, :unsupported_signing_algorithm} =
             IdentityWritePolicy.validate("ed25519")
  end

  test "verification support is independent from the write policy" do
    Application.put_env(:ansible_relay, :identity_write_algorithms, ["p256-sha256"])

    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    message = "historical signed object"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])

    assert AnsibleRelay.SigVerifier.verify_identity(
             "ed25519",
             Base.encode16(public_key, case: :lower),
             message,
             Base.encode16(signature, case: :lower)
           )
  end
end
