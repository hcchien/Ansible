defmodule AnsibleRelay.SnapshotSigner do
  @moduledoc """
  Relay server signing key for op snapshots (service architecture plan §Phase 2.3).

  The relay had no server-side signing key before Phase 2 — it only *verifies*
  author signatures (`AnsibleRelay.SigVerifier`). Snapshots need the relay to
  *attest* "this is the op state I observed up to cursor N", so this module
  introduces a configured Ed25519 key:

      config :ansible_relay, :snapshot_signing_key_hex, "<64-hex-byte Ed25519 seed>"

  ## Key source & precedence

    1. `:snapshot_signing_key_hex` app env (production: set from a secret).
    2. In dev/test only, a deterministic per-node key derived from the node
       cookie + name, so snapshots are signed and verifiable without operator
       setup. A WARNING is logged so this is never silently relied on in prod.

  The value is a 32-byte Ed25519 *seed* in lowercase hex (64 chars). The public
  key is derived from it and embedded in every snapshot row, so a key rotation
  does not retroactively invalidate published snapshots (consumers verify
  against the pinned `signing_public_key_hex`).

  Signatures are over the snapshot CID (the content address), produced with
  OTP's native Ed25519 — no NIF round-trip needed for the rare sign path.
  """

  require Logger

  @doc """
  Returns `{:ok, {public_key_hex, private_key_seed}}` for the configured key,
  or `{:error, reason}` if a configured key is malformed.
  """
  @spec keypair() :: {:ok, {String.t(), binary()}} | {:error, atom()}
  def keypair do
    case Application.get_env(:ansible_relay, :snapshot_signing_key_hex) do
      hex when is_binary(hex) ->
        from_seed_hex(hex)

      nil ->
        {:ok, derived_dev_keypair()}
    end
  end

  @doc "Hex (lowercase) Ed25519 public key of the active snapshot signing key."
  @spec public_key_hex() :: {:ok, String.t()} | {:error, atom()}
  def public_key_hex do
    with {:ok, {pub_hex, _seed}} <- keypair(), do: {:ok, pub_hex}
  end

  @doc """
  Signs `message` (a binary) with the snapshot key. Returns the lowercase-hex
  signature plus the signer's public key hex, or `{:error, reason}`.
  """
  @spec sign(binary()) ::
          {:ok, %{signature: String.t(), public_key_hex: String.t()}} | {:error, atom()}
  def sign(message) when is_binary(message) do
    with {:ok, {pub_hex, seed}} <- keypair() do
      # OTP's Ed25519 signer takes the 32-byte seed as the private key.
      signature =
        :crypto.sign(:eddsa, :none, message, [seed, :ed25519])
        |> Base.encode16(case: :lower)

      {:ok, %{signature: signature, public_key_hex: pub_hex}}
    end
  end

  @doc """
  Verifies a snapshot signature against an explicit public key hex (the one
  pinned on the snapshot row). Returns a strict boolean. Independently
  recomputable by any consumer — no relay state required.
  """
  @spec verify(binary(), String.t(), String.t()) :: boolean()
  def verify(message, signature_hex, public_key_hex)
      when is_binary(message) and is_binary(signature_hex) and is_binary(public_key_hex) do
    AnsibleRelay.SigVerifier.verify_ed25519(public_key_hex, message, signature_hex)
  end

  def verify(_message, _signature_hex, _public_key_hex), do: false

  # --- Internals ---

  defp from_seed_hex(hex) do
    with true <- byte_size(hex) == 64,
         {:ok, seed} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(seed) == 32 do
      {public_key, _private} = :crypto.generate_key(:eddsa, :ed25519, seed)
      {:ok, {Base.encode16(public_key, case: :lower), seed}}
    else
      _ -> {:error, :invalid_snapshot_signing_key}
    end
  end

  # Dev/test fallback: deterministic per-BEAM seed so snapshots verify in tests
  # and local runs without operator key setup. Never used when the app env key
  # is set; logged so a misconfigured prod is loud, not silent.
  defp derived_dev_keypair do
    Logger.warning(
      "SnapshotSigner: :snapshot_signing_key_hex is unset; using a derived dev/test key. " <>
        "Set ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX in production."
    )

    seed =
      :crypto.hash(
        :sha256,
        "ansible_relay.snapshot_signer.dev." <>
          to_string(node()) <> "." <> to_string(:erlang.get_cookie())
      )

    {public_key, _private} = :crypto.generate_key(:eddsa, :ed25519, seed)
    {Base.encode16(public_key, case: :lower), seed}
  end
end
