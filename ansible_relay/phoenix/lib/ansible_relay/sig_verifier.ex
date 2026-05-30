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

  @secp256k1_p 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @secp256k1_g {
    0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
    0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
  }

  @spec verify_schnorr_bip340(String.t(), String.t(), String.t()) :: boolean()
  def verify_schnorr_bip340(public_key_hex, message_hash_hex, signature_hex)
      when is_binary(public_key_hex) and is_binary(message_hash_hex) and
             is_binary(signature_hex) do
    with {:ok, public_key} <- decode_hex(public_key_hex, 32),
         {:ok, message_hash} <- decode_hex(message_hash_hex, 32),
         {:ok, signature} <- decode_hex(signature_hex, 64),
         <<public_x::unsigned-big-256>> <- public_key,
         true <- public_x < @secp256k1_p,
         {:ok, public_point} <- lift_x(public_x),
         <<r::unsigned-big-256, s::unsigned-big-256>> <- signature,
         true <- r < @secp256k1_p,
         true <- s < @secp256k1_n do
      e =
        tagged_hash(
          "BIP0340/challenge",
          <<r::unsigned-big-256, public_key::binary, message_hash::binary>>
        )
        |> binary_to_int()
        |> rem(@secp256k1_n)

      case point_add(point_mul(s, @secp256k1_g), point_mul(@secp256k1_n - e, public_point)) do
        nil -> false
        {x, y} -> even?(y) and x == r
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def verify_schnorr_bip340(_public_key_hex, _message_hash_hex, _signature_hex), do: false

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

  defp tagged_hash(tag, message) do
    tag_hash = :crypto.hash(:sha256, tag)
    :crypto.hash(:sha256, tag_hash <> tag_hash <> message)
  end

  defp lift_x(x) do
    c = mod(x * x * x + 7, @secp256k1_p)
    y = mod_pow(c, div(@secp256k1_p + 1, 4), @secp256k1_p)

    if mod(y * y, @secp256k1_p) == c do
      {:ok, {x, if(even?(y), do: y, else: @secp256k1_p - y)}}
    else
      :error
    end
  end

  defp point_mul(scalar, point) do
    do_point_mul(scalar, point, nil)
  end

  defp do_point_mul(0, _point, result), do: result

  defp do_point_mul(scalar, point, result) do
    next_result = if rem(scalar, 2) == 1, do: point_add(result, point), else: result
    do_point_mul(div(scalar, 2), point_add(point, point), next_result)
  end

  defp point_add(nil, point), do: point
  defp point_add(point, nil), do: point

  defp point_add({x1, y1}, {x2, y2}) do
    cond do
      x1 == x2 and mod(y1 + y2, @secp256k1_p) == 0 ->
        nil

      x1 == x2 and y1 == y2 ->
        lambda = mod(3 * x1 * x1 * mod_inverse(2 * y1, @secp256k1_p), @secp256k1_p)
        point_from_lambda(lambda, x1, y1, x2)

      true ->
        lambda = mod((y2 - y1) * mod_inverse(x2 - x1, @secp256k1_p), @secp256k1_p)
        point_from_lambda(lambda, x1, y1, x2)
    end
  end

  defp point_from_lambda(lambda, x1, y1, x2) do
    x3 = mod(lambda * lambda - x1 - x2, @secp256k1_p)
    y3 = mod(lambda * (x1 - x3) - y1, @secp256k1_p)
    {x3, y3}
  end

  defp mod_inverse(value, modulus) do
    case egcd(mod(value, modulus), modulus) do
      {1, inverse, _} -> mod(inverse, modulus)
      _ -> raise ArgumentError, "inverse does not exist"
    end
  end

  defp egcd(0, b), do: {b, 0, 1}

  defp egcd(a, b) do
    {g, x, y} = egcd(rem(b, a), a)
    {g, y - div(b, a) * x, x}
  end

  defp mod(value, modulus) do
    result = rem(value, modulus)
    if result < 0, do: result + modulus, else: result
  end

  defp mod_pow(_base, 0, _modulus), do: 1

  defp mod_pow(base, exponent, modulus) do
    do_mod_pow(mod(base, modulus), exponent, modulus, 1)
  end

  defp do_mod_pow(_base, 0, _modulus, result), do: result

  defp do_mod_pow(base, exponent, modulus, result) do
    next_result = if rem(exponent, 2) == 1, do: mod(result * base, modulus), else: result
    do_mod_pow(mod(base * base, modulus), div(exponent, 2), modulus, next_result)
  end

  defp even?(value), do: rem(value, 2) == 0

  defp binary_to_int(binary) do
    :binary.decode_unsigned(binary, :big)
  end
end
