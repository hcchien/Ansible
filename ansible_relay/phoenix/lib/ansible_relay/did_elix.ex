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
end
