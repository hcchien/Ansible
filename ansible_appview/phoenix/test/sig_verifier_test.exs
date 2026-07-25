defmodule AnsibleAppview.SigVerifierTest do
  use ExUnit.Case, async: true

  alias AnsibleAppview.SigVerifier

  test "verifies P-256 DER and legacy IEEE-P1363 signatures" do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1)
    message = "signed operation"
    der = :crypto.sign(:ecdsa, :sha256, message, [private_key, :secp256r1])

    assert SigVerifier.verify_identity(
             "p256-sha256",
             Base.encode16(public_key, case: :lower),
             message,
             Base.encode16(der, case: :lower)
           )

    <<48, _sequence_length, 2, r_length, rest::binary>> = der
    <<r::binary-size(r_length), 2, s_length, s::binary-size(s_length)>> = rest
    p1363 = left_pad_32(r) <> left_pad_32(s)

    assert SigVerifier.verify_identity(
             "p256-sha256",
             Base.encode16(public_key, case: :lower),
             message,
             Base.encode16(p1363, case: :lower)
           )
  end

  test "rejects an unsupported algorithm" do
    refute SigVerifier.verify_identity("unknown", "00", "message", "00")
  end

  defp left_pad_32(<<0, rest::binary>>) when byte_size(rest) == 32, do: rest
  defp left_pad_32(bytes), do: :binary.copy(<<0>>, 32 - byte_size(bytes)) <> bytes
end
