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

  test "protected modes fail closed before verifier enforcement ships" do
    policy =
      BoardAccessPolicy.default()
      |> Map.put("discovery", "credential_required")
      |> Map.put("requirements", %{
        "member" => %{"credential_type" => "PoliticalPartyMembershipCredential"}
      })

    assert {:error, :protected_access_policy_not_enabled} =
             BoardAccessPolicy.validate(policy)
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
end
