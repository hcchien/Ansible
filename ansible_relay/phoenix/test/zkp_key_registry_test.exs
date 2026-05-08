defmodule AnsibleRelay.ZkpKeyRegistryTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.ZkpKeyRegistry

  setup do
    previous = Application.get_env(:ansible_relay, :zkp_verification_keys)
    previous_allow_dev = Application.get_env(:ansible_relay, :allow_dev_zkp_proofs)

    Application.put_env(:ansible_relay, :zkp_verification_keys, [
      %{version: "passport_v1", hash: "sha256:active-hash", status: :active},
      %{version: "passport_v0", hash: "sha256:old-hash", status: :retired},
      %{version: "passport_v1_dev", hash: "sha256:dev-passport-v1-placeholder", status: :active}
    ])

    Application.put_env(:ansible_relay, :allow_dev_zkp_proofs, false)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ansible_relay, :zkp_verification_keys)
      else
        Application.put_env(:ansible_relay, :zkp_verification_keys, previous)
      end

      if is_nil(previous_allow_dev) do
        Application.delete_env(:ansible_relay, :allow_dev_zkp_proofs)
      else
        Application.put_env(:ansible_relay, :allow_dev_zkp_proofs, previous_allow_dev)
      end
    end)

    :ok
  end

  test "verify accepts an active pinned version and hash" do
    assert :ok = ZkpKeyRegistry.verify("passport_v1", "sha256:active-hash")
  end

  test "verify rejects unsupported circuit versions" do
    assert {:error, :unsupported_zkp_circuit} =
             ZkpKeyRegistry.verify("passport_v999", "sha256:active-hash")
  end

  test "verify rejects inactive circuit versions" do
    assert {:error, :inactive_zkp_circuit} =
             ZkpKeyRegistry.verify("passport_v0", "sha256:old-hash")
  end

  test "verify rejects mismatched hashes" do
    assert {:error, :verification_key_hash_mismatch} =
             ZkpKeyRegistry.verify("passport_v1", "sha256:wrong-hash")
  end

  test "verify rejects development verification keys unless explicitly enabled" do
    assert {:error, :development_zkp_disabled} =
             ZkpKeyRegistry.verify("passport_v1_dev", "sha256:dev-passport-v1-placeholder")

    Application.put_env(:ansible_relay, :allow_dev_zkp_proofs, true)

    assert :ok =
             ZkpKeyRegistry.verify("passport_v1_dev", "sha256:dev-passport-v1-placeholder")
  end
end
