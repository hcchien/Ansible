defmodule AnsibleRelay.GossipsubTopicTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.GossipsubTopic

  test "build returns canonical topic for valid network and scope" do
    assert {:ok, "/ansible/ops/v1/mainnet/global"} =
             GossipsubTopic.build("mainnet", "global")
  end

  test "validate accepts canonical topics" do
    assert :ok = GossipsubTopic.validate("/ansible/ops/v1/mainnet/global")
    assert :ok = GossipsubTopic.validate("/ansible/ops/v1/testnet/global")
    assert :ok = GossipsubTopic.validate("/ansible/ops/v1/devnet/genesis-lab")
    assert :ok = GossipsubTopic.validate("/ansible/ops/v1/local/hcchien-mbp")
  end

  test "validate rejects shorthand prefix as a publish topic" do
    assert {:error, :invalid_topic_format} =
             GossipsubTopic.validate("/ansible/ops/v1")
  end

  test "validate rejects unsupported topic version" do
    assert {:error, :unsupported_topic_version} =
             GossipsubTopic.validate("/ansible/ops/v2/mainnet/global")
  end

  test "validate rejects unknown network" do
    assert {:error, :unknown_network} =
             GossipsubTopic.validate("/ansible/ops/v1/private/global")
  end

  test "validate rejects invalid scope" do
    assert {:error, :invalid_scope} =
             GossipsubTopic.validate("/ansible/ops/v1/mainnet/BadScope")
  end

  test "mainnet_global returns production public Ops topic" do
    assert GossipsubTopic.mainnet_global() == "/ansible/ops/v1/mainnet/global"
  end
end
