defmodule AnsibleRelay.ZkpKeyRegistry do
  @moduledoc """
  Pinned ZKP verification key registry.

  Phase 1 anchoring must declare the circuit version and Verification Key hash
  used to produce the proof. The relay accepts only configured, active entries.
  """

  @app :ansible_relay

  @type key_entry :: %{
          required(:version) => String.t(),
          required(:hash) => String.t(),
          optional(:status) => atom()
        }

  @doc "Return the configured ZKP Verification Key entries."
  @spec list() :: [key_entry()]
  def list do
    Application.get_env(@app, :zkp_verification_keys, [])
  end

  @doc "Find a Verification Key entry by circuit version."
  @spec find(String.t()) :: {:ok, key_entry()} | :not_found
  def find(version) when is_binary(version) do
    case Enum.find(list(), &(&1.version == version)) do
      nil -> :not_found
      entry -> {:ok, entry}
    end
  end

  @doc "Verify that the client supplied an active pinned key hash."
  @spec verify(String.t(), String.t()) ::
          :ok
          | {:error, :unsupported_zkp_circuit}
          | {:error, :inactive_zkp_circuit}
          | {:error, :verification_key_hash_mismatch}
          | {:error, :development_zkp_disabled}
  def verify(version, hash) when is_binary(version) and is_binary(hash) do
    case find(version) do
      {:ok, %{hash: ^hash} = entry} ->
        verify_matching_entry(entry)

      {:ok, _entry} ->
        {:error, :verification_key_hash_mismatch}

      :not_found ->
        {:error, :unsupported_zkp_circuit}
    end
  end

  defp verify_matching_entry(%{version: version, hash: hash, status: :active}) do
    if development_key?(version, hash) and
         not Application.get_env(@app, :allow_dev_zkp_proofs, false) do
      {:error, :development_zkp_disabled}
    else
      :ok
    end
  end

  defp verify_matching_entry(%{hash: _hash}), do: {:error, :inactive_zkp_circuit}

  defp development_key?(version, hash) do
    String.contains?(version, "_dev") or
      String.contains?(hash, "dev-") or
      String.contains?(hash, "placeholder")
  end
end
