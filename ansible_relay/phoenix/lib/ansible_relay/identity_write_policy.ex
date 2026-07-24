defmodule AnsibleRelay.IdentityWritePolicy do
  @moduledoc """
  Negotiates algorithms accepted for new first-party user-identity writes.

  Verification code intentionally remains multi-algorithm so historical
  objects stay independently readable. This policy is applied only at write
  boundaries.
  """

  @default_algorithms ["p256-sha256"]

  @spec allowed?(term()) :: boolean()
  def allowed?(algorithm) when is_binary(algorithm) do
    algorithm in Application.get_env(
      :ansible_relay,
      :identity_write_algorithms,
      @default_algorithms
    )
  end

  def allowed?(_algorithm), do: false

  @doc """
  Content-bound WebAuthn author proofs are a separate P-256 verification rail.
  They are accepted only after DID delegation and UV assertion verification;
  this does not make the ordinary publication-intent endpoint accept WebAuthn
  assertion blobs as direct signatures.
  """
  def allowed_author_proof?("webauthn-p256-sha256"), do: true
  def allowed_author_proof?(algorithm), do: allowed?(algorithm)

  @spec validate(term()) :: :ok | {:error, :unsupported_signing_algorithm}
  def validate(algorithm) do
    if allowed?(algorithm), do: :ok, else: {:error, :unsupported_signing_algorithm}
  end

  @spec expected() :: [String.t()]
  def expected do
    Application.get_env(
      :ansible_relay,
      :identity_write_algorithms,
      @default_algorithms
    )
  end
end
