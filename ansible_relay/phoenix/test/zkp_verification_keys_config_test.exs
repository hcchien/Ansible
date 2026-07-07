defmodule AnsibleRelay.Config.ZkpVerificationKeysTest do
  use ExUnit.Case, async: true

  # config/runtime.exs (prod branch) calls load_prod!/1 with
  # System.get_env("ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS"). These tests pin the
  # fail-closed contract: unset ⇒ no active keys (the config.exs dev
  # placeholders never survive into prod), set ⇒ strictly validated JSON.

  alias AnsibleRelay.Config.ZkpVerificationKeys

  @real_hash "sha256:" <> String.duplicate("ab12", 16)

  describe "load_prod!/1 with the env var unset" do
    test "returns [] so the dev placeholders from config.exs are overridden" do
      assert ZkpVerificationKeys.load_prod!(nil) == []
    end
  end

  describe "load_prod!/1 with valid JSON" do
    test "parses entries into the config.exs map shape" do
      json =
        Jason.encode!([
          %{version: "passport_v1_groth16_bn254", hash: @real_hash, status: "active"},
          %{version: "passport_v0", hash: @real_hash, status: "retired"}
        ])

      assert ZkpVerificationKeys.load_prod!(json) == [
               %{version: "passport_v1_groth16_bn254", hash: @real_hash, status: :active},
               %{version: "passport_v0", hash: @real_hash, status: :retired}
             ]
    end
  end

  describe "load_prod!/1 rejections (fail closed at boot)" do
    test "rejects the dev placeholder hashes shipped in config.exs" do
      for placeholder <- [
            "sha256:dev-vk-hash-placeholder",
            "sha256:dev-passport-v1-placeholder"
          ] do
        json = Jason.encode!([%{version: "passport_v1_dev", hash: placeholder, status: "active"}])

        assert_raise ArgumentError, ~r/placeholder/i, fn ->
          ZkpVerificationKeys.load_prod!(json)
        end
      end
    end

    test "rejects a hash that is not sha256:<64 lowercase hex>" do
      for bad_hash <- [
            "sha256:" <> String.duplicate("A", 64),
            "sha256:" <> String.duplicate("a", 63),
            "md5:" <> String.duplicate("a", 64),
            String.duplicate("a", 64)
          ] do
        json = Jason.encode!([%{version: "v1", hash: bad_hash, status: "active"}])

        assert_raise ArgumentError, fn -> ZkpVerificationKeys.load_prod!(json) end
      end
    end

    test "rejects an unknown status" do
      json = Jason.encode!([%{version: "v1", hash: @real_hash, status: "pending"}])

      assert_raise ArgumentError, ~r/"active" or "retired"/, fn ->
        ZkpVerificationKeys.load_prod!(json)
      end
    end

    test "rejects malformed JSON, non-array JSON, and an empty array" do
      for bad <- ["{not json", ~s({"version":"v1"}), "[]", "42"] do
        assert_raise ArgumentError, fn -> ZkpVerificationKeys.load_prod!(bad) end
      end
    end

    test "rejects entries missing fields or with an empty version" do
      for entry <- [
            %{hash: @real_hash, status: "active"},
            %{version: "v1", status: "active"},
            %{version: "v1", hash: @real_hash},
            %{version: "", hash: @real_hash, status: "active"}
          ] do
        json = Jason.encode!([entry])

        assert_raise ArgumentError, fn -> ZkpVerificationKeys.load_prod!(json) end
      end
    end
  end
end
