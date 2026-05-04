defmodule AnsibleRelay.ZkpKeyRegistryTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.ZkpKeyRegistry

  setup do
    previous = Application.get_env(:ansible_relay, :zkp_verification_keys)

    Application.put_env(:ansible_relay, :zkp_verification_keys, [
      %{version: "passport_v1", hash: "sha256:active-hash", status: :active},
      %{version: "passport_v0", hash: "sha256:old-hash", status: :retired}
    ])

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ansible_relay, :zkp_verification_keys)
      else
        Application.put_env(:ansible_relay, :zkp_verification_keys, previous)
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
end
