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

  test "unknown claim operators and sensitive claims fail closed" do
    policy = membership_policy()
    member = policy["requirements"]["member"]

    assert {:error, :invalid_claim_policy} =
             put_in(policy, ["requirements", "member"], %{
               member
               | "claims" => [%{"path" => "membership", "op" => "regex", "value" => true}]
             })
             |> BoardAccessPolicy.validate()

    assert {:error, :invalid_claim_policy} =
             put_in(policy, ["requirements", "member"], %{
               member
               | "credential_type" => "OperatorDefinedAdminCredential",
                 "claims" => [%{"path" => "nationalId", "op" => "equals", "value" => "A123"}]
             })
             |> BoardAccessPolicy.validate()
  end

  test "manifest-defined credential type and configuration are accepted" do
    policy =
      membership_policy()
      |> put_in(
        ["requirements", "member"],
        %{
          "credential_configuration_id" => "party-member-v2",
          "credential_type" => "OrganizationMembershipCredential",
          "trusted_issuers" => ["did:web:party.example"],
          "claims" => [%{"path" => "membershipActive", "op" => "equals", "value" => true}],
          "holder_binding" => "required",
          "status" => %{"required" => true, "max_age_seconds" => 300}
        }
      )

    assert :ok = BoardAccessPolicy.validate(policy)
  end

  test "all App board-policy editor presets satisfy the Relay v1 schema" do
    public = app_policy(nil, false)

    taiwan_citizen =
      app_requirement(
        "NationalityCredential",
        "nationality",
        "TWN"
      )

    adult =
      app_requirement(
        "AgeOver18Credential",
        "ageOver18",
        true
      )

    organization_member =
      app_requirement(
        "PoliticalPartyMembershipCredential",
        "membership",
        true
      )

    custom =
      app_requirement(
        "OrganizationMembershipCredential",
        "membershipActive",
        true
      )
      |> Map.put("credential_configuration_id", "party-member-v2")

    policies = [
      public,
      # verified-human posting uses the same access JSON as public; its
      # min_post_tier lives in the separately validated posting_policy.
      public,
      app_policy(taiwan_citizen, false),
      app_policy(adult, false),
      app_policy(organization_member, false),
      app_policy(organization_member, true),
      app_policy(custom, false),
      app_policy(custom, true)
    ]

    assert Enum.all?(policies, &(BoardAccessPolicy.validate(&1) == :ok))
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

  defp app_policy(nil, false), do: BoardAccessPolicy.default()

  defp app_policy(requirement, restricted?) do
    BoardAccessPolicy.default()
    |> Map.put("discovery", if(restricted?, do: "credential_required", else: "public"))
    |> Map.put("read", %{"requirement" => if(restricted?, do: "member", else: "public")})
    |> Map.put("post", %{"requirement" => "member"})
    |> Map.put("requirements", %{"member" => requirement})
    |> Map.put("content_visibility", if(restricted?, do: "host_visible", else: "public"))
    |> Map.put("federation", if(restricted?, do: "disabled", else: "enabled"))
  end

  defp app_requirement(credential_type, claim_path, claim_value) do
    %{
      "credential_type" => credential_type,
      "trusted_issuers" => ["did:web:issuer.example"],
      "claims" => [%{"path" => claim_path, "op" => "equals", "value" => claim_value}],
      "holder_binding" => "required",
      "status" => %{"required" => true, "max_age_seconds" => 300}
    }
  end
end
