defmodule AnsibleAppview.SigVerifier do
  @moduledoc """
  Ed25519 verification via OTP's native crypto. The AppView re-verifies every op
  it ingests (double verification); clients re-verify again on read. Development
  stub signatures are never accepted.

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

  defp decode_hex(hex, expected_bytes) when is_binary(hex) do
    with true <- byte_size(hex) == expected_bytes * 2,
         {:ok, bytes} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(bytes) == expected_bytes do
      {:ok, bytes}
    else
      _ -> :error
    end
  end
end
