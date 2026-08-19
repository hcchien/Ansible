defmodule AnsibleRelay.DidElix do
  @moduledoc """
  Canonical `did:elix` derivation + self-certification (layered identity).

  `did:elix:<suffix>` where `<suffix>` is
  `base32_lower_nopad(sha256(stable_fingerprint)[0..16])` over the SAME stable
  fingerprint bytes as the Dart `deriveDidElix`
  (`ansible_core/store/lib/src/entities/identity_anchor.dart`):

      {"method":"did:elix","v":1,"identity_key":<hex>,"handle":<handle>,"custody_class":<class>}

  fixed key order, no whitespace. Because the identifier is a hash of the
  identity key + handle, ANY relay can confirm a resolved anchor is genuine
  without trusting whoever served it: `matches?/3` recomputes the DID and
  compares. This is what makes cross-relay resolution answers verifiable rather
  than authoritative (Base Rule 1).
  """

  @base58btc_alphabet "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  @doc "Derive the did:elix for an identity key + handle (+ custody class)."
  def derive(identity_key, handle, custody_class \\ "software", algorithm \\ "ed25519")
      when is_binary(identity_key) and is_binary(handle) and is_binary(custody_class) do
    body =
      if algorithm == "ed25519" do
        ~s({"method":"did:elix","v":1,"identity_key":) <>
          Jason.encode!(identity_key) <>
          ~s(,"handle":) <>
          Jason.encode!(handle) <>
          ~s(,"custody_class":) <>
          Jason.encode!(custody_class) <>
          "}"
      else
        ~s({"method":"did:elix","v":2,"identity_key":) <>
          Jason.encode!(identity_key) <>
          ~s(,"identity_key_algorithm":) <>
          Jason.encode!(algorithm) <>
          ~s(,"handle":) <>
          Jason.encode!(handle) <>
          ~s(,"custody_class":) <>
          Jason.encode!(custody_class) <>
          "}"
      end

    suffix =
      :sha256
      |> :crypto.hash(body)
      |> binary_part(0, 16)
      |> Base.encode32(case: :lower, padding: false)

    "did:elix:" <> suffix
  end

  @doc """
  True when `did` is the self-certifying did:elix of `(identity_key, handle,
  custody_class)`. Used to validate a resolved anchor before trusting it.
  """
  def matches?(did, identity_key, handle, custody_class \\ "software")

  def matches?(did, identity_key, handle, custody_class)
      when is_binary(did) and is_binary(identity_key) and is_binary(handle) do
    derive(identity_key, handle, custody_class) == did
  end

  def matches?(_did, _identity_key, _handle, _custody_class), do: false

  def matches?(did, identity_key, handle, custody_class, algorithm)
      when is_binary(did) and is_binary(identity_key) and is_binary(handle),
      do: derive(identity_key, handle, custody_class, algorithm) == did

  @doc "Canonical did:elix v1 genesis commitment, with normative key order."
  def canonical_v1_commitment(commitment) when is_map(commitment) do
    ~s({"method":"did:elix","method_version":1,"genesis_key":) <>
      Jason.encode!(commitment["genesis_key"] || commitment[:genesis_key]) <>
      ~s(,"genesis_nonce":) <>
      Jason.encode!(commitment["genesis_nonce"] || commitment[:genesis_nonce]) <>
      "}"
  end

  @doc "Derive the stable v1 DID from its immutable public commitment."
  def derive_v1(commitment) when is_map(commitment) do
    with :ok <- validate_v1_commitment(commitment) do
      suffix =
        :sha256
        |> :crypto.hash(canonical_v1_commitment(commitment))
        |> Base.encode32(case: :lower, padding: false)

      {:ok, "did:elix:z" <> suffix}
    end
  end

  def derive_v1(_), do: {:error, :invalid_genesis_commitment}

  def matches_v1?(did, commitment) when is_binary(did) and is_map(commitment) do
    derive_v1(commitment) == {:ok, did}
  end

  def matches_v1?(_, _), do: false

  @doc "Validate all normative v1 commitment fields and reject extensions."
  def validate_v1_commitment(commitment) when is_map(commitment) do
    method = commitment["method"] || commitment[:method]
    version = commitment["method_version"] || commitment[:method_version]
    key = commitment["genesis_key"] || commitment[:genesis_key]
    nonce = commitment["genesis_nonce"] || commitment[:genesis_nonce]

    allowed = MapSet.new(~w(method method_version genesis_key genesis_nonce))
    actual = commitment |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()

    cond do
      actual != allowed ->
        {:error, :invalid_genesis_commitment}

      method != "did:elix" ->
        {:error, :invalid_genesis_commitment}

      version != 1 ->
        {:error, :invalid_genesis_commitment}

      not is_binary(key) or
          not String.match?(key, ~r/\A(?:[0-9a-f]{64}|04[0-9a-f]{128})\z/) ->
        {:error, :invalid_genesis_commitment}

      not is_binary(nonce) or not String.match?(nonce, ~r/\A[0-9a-f]{64}\z/) ->
        {:error, :invalid_genesis_commitment}

      true ->
        :ok
    end
  end

  def validate_v1_commitment(_), do: {:error, :invalid_genesis_commitment}

  @doc "Canonical v1 registration proof signed by the genesis identity key."
  def registration_payload(nonce, did, commitment)
      when is_binary(nonce) and is_binary(did) and is_map(commitment) do
    ~s({"type":"io.trisaura.identity.registration","version":1,"nonce":) <>
      Jason.encode!(nonce) <>
      ~s(,"did":) <>
      Jason.encode!(did) <>
      ~s(,"genesis_commitment":) <>
      canonical_v1_commitment(commitment) <>
      "}"
  end

  @doc "Encode a raw Ed25519 public key as its multicodec base58btc value."
  def ed25519_multibase(public_key_hex) when is_binary(public_key_hex) do
    with {:ok, public_key} <- Base.decode16(public_key_hex, case: :mixed),
         true <- byte_size(public_key) == 32 do
      {:ok, "z" <> base58btc(<<0xED, 0x01, public_key::binary>>)}
    else
      _ -> {:error, :invalid_public_key}
    end
  end

  def ed25519_multibase(_), do: {:error, :invalid_public_key}

  defp base58btc(bytes) do
    leading_zeroes =
      bytes
      |> :binary.bin_to_list()
      |> Enum.take_while(&(&1 == 0))
      |> length()

    String.duplicate("1", leading_zeroes) <>
      encode_base58_integer(:binary.decode_unsigned(bytes), "")
  end

  defp encode_base58_integer(0, encoded), do: encoded

  defp encode_base58_integer(number, encoded) do
    digit = binary_part(@base58btc_alphabet, rem(number, 58), 1)
    encode_base58_integer(div(number, 58), digit <> encoded)
  end
end
