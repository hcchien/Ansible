defmodule AnsibleRelay.ForumHost.BoardAccessPolicyTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.ForumHost.BoardAccessPolicy

  test "default policy is an explicit open and public policy" do
    policy = BoardAccessPolicy.default()

    assert :ok = BoardAccessPolicy.validate(policy)
    assert policy["discovery"] == "public"
    assert policy["read"]["requirement"] == "public"
    assert policy["content_visibility"] == "public"
  end

  test "credential policy is strict and produces board-scoped decisions" do
    policy = membership_policy()

    assert :ok = BoardAccessPolicy.validate(policy)

    evidence = %{
      "credential_type" => "PoliticalPartyMembershipCredential",
      "issuer" => "did:elix:org:ntp",
      "holder_bound" => true,
      "status" => "active",
      "claims" => %{"membership" => true}
    }

    assert :ok = BoardAccessPolicy.evaluate(policy, :read, evidence)

    assert {:error, :issuer_not_trusted} =
             BoardAccessPolicy.evaluate(policy, :read, %{
               evidence
               | "issuer" => "did:example:attacker"
             })

    assert {:error, :holder_binding_failed} =
             BoardAccessPolicy.evaluate(policy, :read, %{evidence | "holder_bound" => false})
  end

  test "unknown fields and unsafe capability TTLs are rejected" do
    assert {:error, :unknown_access_policy_field} =
             BoardAccessPolicy.default()
             |> Map.put("script", "allow()")
             |> BoardAccessPolicy.validate()

    assert {:error, :invalid_capability_ttl} =
             BoardAccessPolicy.default()
             |> Map.put("capability_ttl_seconds", 86_400)
             |> BoardAccessPolicy.validate()
  end

  test "protected board cannot federate and encrypted mode remains gated" do
    assert {:error, :protected_board_federation_enabled} =
             membership_policy()
             |> Map.put("federation", "enabled")
             |> BoardAccessPolicy.validate()

    assert {:error, :encrypted_boards_not_enabled} =
             membership_policy()
             |> Map.put("content_visibility", "end_to_end_encrypted")
             |> BoardAccessPolicy.validate()
  end

  test "unknown claim operators and self-defined credential types fail closed" do
    policy = membership_policy()
    member = policy["requirements"]["member"]

    assert {:error, :invalid_claim_policy} =
             put_in(policy, ["requirements", "member"], %{
               member
               | "claims" => [%{"path" => "membership", "op" => "regex", "value" => true}]
             })
             |> BoardAccessPolicy.validate()

    assert {:error, :unsupported_credential_type} =
             put_in(policy, ["requirements", "member"], %{
               member
               | "credential_type" => "OperatorDefinedAdminCredential"
             })
             |> BoardAccessPolicy.validate()
  end

  defp membership_policy do
    requirement = %{
      "credential_type" => "PoliticalPartyMembershipCredential",
      "trusted_issuers" => ["did:elix:org:ntp"],
      "claims" => [%{"path" => "membership", "op" => "equals", "value" => true}],
      "holder_binding" => "required",
      "status" => %{"required" => true, "max_age_seconds" => 300}
    }

    BoardAccessPolicy.default()
    |> Map.put("discovery", "credential_required")
    |> Map.put("read", %{"requirement" => "member"})
    |> Map.put("post", %{"requirement" => "member"})
    |> Map.put("requirements", %{"member" => requirement})
    |> Map.put("content_visibility", "host_visible")
    |> Map.put("federation", "disabled")
  end
end
