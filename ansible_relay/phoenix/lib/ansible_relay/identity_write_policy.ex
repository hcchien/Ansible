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
