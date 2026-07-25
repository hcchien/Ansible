defmodule AnsibleAppview.SigVerifier do
  @moduledoc """
  Identity signature verification via OTP's native crypto. The AppView
  re-verifies every op it ingests (double verification); clients re-verify
  again on read. Development stub signatures are never accepted.

  Phase C may replace this with a Rustler batch verifier for throughput; the
  contract (hex pubkey + raw message + hex signature -> bool) stays the same.
  """

  @spec verify_ed25519(String.t(), binary(), String.t()) :: boolean()
  def verify_ed25519(public_key_hex, message, signature_hex)
      when is_binary(public_key_hex) and is_binary(message) and is_binary(signature_hex) do
    with {:ok, public_key} <- decode_hex(public_key_hex, 32),
         {:ok, signature} <- decode_hex(signature_hex, 64) do
      :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def verify_ed25519(_public_key_hex, _message, _signature_hex), do: false

  @doc "Verify an op using the identity algorithm declared by the Relay."
  @spec verify_identity(String.t(), String.t(), binary(), String.t()) :: boolean()
  def verify_identity("ed25519", public_key_hex, message, signature_hex),
    do: verify_ed25519(public_key_hex, message, signature_hex)

  def verify_identity("p256-sha256", public_key_hex, message, signature_hex)
      when is_binary(public_key_hex) and is_binary(message) and is_binary(signature_hex) do
    with {:ok, public_key} <- decode_hex(public_key_hex, 65),
         <<4, _::binary-size(64)>> <- public_key,
         {:ok, signature} <- decode_p256_signature(signature_hex) do
      :crypto.verify(:ecdsa, :sha256, message, signature, [public_key, :secp256r1]) === true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def verify_identity(_algorithm, _public_key_hex, _message, _signature_hex), do: false

  # Current hardware signers emit ASN.1 DER. Earlier dev clients emitted the
  # IEEE-P1363 r||s form, and those already-accepted immutable Relay ops must
  # remain independently verifiable when AppView rebuilds its projection.
  defp decode_p256_signature(signature_hex) do
    with {:ok, signature} <- decode_variable_hex(signature_hex) do
      case signature do
        <<r::binary-size(32), s::binary-size(32)>> ->
          {:ok, encode_ecdsa_der(r, s)}

        der when byte_size(der) in 68..72 ->
          {:ok, der}

        _ ->
          :error
      end
    end
  end

  defp encode_ecdsa_der(r, s) do
    encoded_r = encode_der_integer(r)
    encoded_s = encode_der_integer(s)
    body =
      <<2, byte_size(encoded_r), encoded_r::binary, 2, byte_size(encoded_s),
        encoded_s::binary>>
    <<48, byte_size(body), body::binary>>
  end

  defp encode_der_integer(bytes) do
    trimmed = trim_leading_zeroes(bytes)

    case trimmed do
      <<first, _::binary>> when first >= 0x80 -> <<0, trimmed::binary>>
      _ -> trimmed
    end
  end

  defp trim_leading_zeroes(<<0, rest::binary>>) when byte_size(rest) > 0,
    do: trim_leading_zeroes(rest)

  defp trim_leading_zeroes(bytes), do: bytes

  defp decode_hex(hex, expected_bytes) when is_binary(hex) do
    with true <- byte_size(hex) == expected_bytes * 2,
         {:ok, bytes} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(bytes) == expected_bytes do
      {:ok, bytes}
    else
      _ -> :error
    end
  end

  defp decode_variable_hex(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> :error
    end
  end
end
