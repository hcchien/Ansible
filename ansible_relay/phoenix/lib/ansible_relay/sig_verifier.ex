defmodule AnsibleRelay.SigVerifierNIF do
  @moduledoc "Rustler NIF binding for Ed25519 verification."
  use Rustler, otp_app: :ansible_relay, crate: "sig_verifier_nif"

  # Called when the NIF is not loaded (fallback)
  def verify_ed25519(_public_key_hex, _message, _signature_hex),
    do: :erlang.nif_error(:nif_not_loaded)
end

defmodule AnsibleRelay.SigVerifier do
  @moduledoc """
  Ed25519 signature verification via Rustler NIF.

  Falls back to OTP's native Ed25519 verifier if the Rustler NIF fails to load.
  Development stub signatures are never accepted by this module.
  """

  require Logger

  @spec verify_ed25519(String.t(), binary(), String.t()) :: boolean()
  def verify_ed25519(public_key_hex, message, signature_hex)
      when is_binary(public_key_hex) and is_binary(message) and is_binary(signature_hex) do
    try do
      AnsibleRelay.SigVerifierNIF.verify_ed25519(public_key_hex, message, signature_hex)
    rescue
      e ->
        Logger.warning(
          "SigVerifier NIF unavailable (#{inspect(e)}), falling back to OTP Ed25519 verification"
        )

        verify_with_otp(public_key_hex, message, signature_hex)
    end
  end

  def verify_ed25519(_public_key_hex, _message, _signature_hex), do: false

  defp verify_with_otp(public_key_hex, message, signature_hex) do
    with {:ok, public_key} <- decode_hex(public_key_hex, 32),
         {:ok, signature} <- decode_hex(signature_hex, 64) do
      :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

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
