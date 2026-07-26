defmodule AnsibleRelay.Web.FediversePreferenceControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{
    Db.FediversePreference,
    DidAccountCache,
    FediversePreferences,
    IdentityCache,
    Repo
  }

  alias AnsibleRelay.Web.{Controllers.FediversePreferenceController, Router}

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp identity(tier \\ "verified_human") do
    did = "did:key:z6MkPreference#{System.unique_integer([:positive])}"
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    public_key_hex = Base.encode16(public_key, case: :lower)
    handle = "pref-#{System.unique_integer([:positive])}"

    IdentityCache.put(did, public_key_hex, "nullifier-#{did}", nil, "ed25519")

    DidAccountCache.put(did, public_key_hex, handle,
      reputation_tier: tier,
      signing_algorithm: "ed25519"
    )

    {did, handle, private_key}
  end

  defp params(did, revision, overrides \\ %{}) do
    Map.merge(
      %{
        "did" => did,
        "enabled" => true,
        "default_note_visibility" => "public",
        "allow_remote_followers" => true,
        "domain_policy" => "open",
        "allowed_domains" => [],
        "blocked_domains" => [],
        "blocked_actors" => [],
        "revision" => revision,
        "signature_scheme" => "ed25519"
      },
      overrides
    )
  end

  defp signed(params, private_key) do
    signature =
      :crypto.sign(
        :eddsa,
        :none,
        FediversePreferenceController.signing_payload(params),
        [private_key, :ed25519]
      )
      |> Base.encode16(case: :lower)

    Map.put(params, "signature", signature)
  end

  defp put_preference(params) do
    conn(:put, "/api/v1/fediverse/preferences", Jason.encode!(params))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  test "verified human can explicitly enable and configure federation" do
    {did, handle, private_key} = identity()

    response =
      params(did, 1, %{
        "domain_policy" => "allowlist",
        "allowed_domains" => ["Social.Example.", "friends.example"],
        "blocked_domains" => ["bad.example"],
        "blocked_actors" => ["https://social.example/users/spammer"]
      })
      |> signed(private_key)
      |> put_preference()

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["actor"] == handle
    assert body["enabled"] == true
    assert body["allowed_domains"] == ["friends.example", "social.example"]
    assert FediversePreferences.enabled_for_did?(did)
  end

  test "enabling requires verified-human tier, while disabling remains possible" do
    {did, _handle, private_key} = identity("basic")

    rejected = params(did, 1) |> signed(private_key) |> put_preference()
    assert rejected.status == 403

    disabled =
      params(did, 2, %{"enabled" => false})
      |> signed(private_key)
      |> put_preference()

    assert disabled.status == 200
    assert Jason.decode!(disabled.resp_body)["enabled"] == false
  end

  test "revision is monotonic and policy blocks domains and actors" do
    {did, handle, private_key} = identity()

    first =
      params(did, 20, %{"blocked_domains" => ["bad.example"]})
      |> signed(private_key)
      |> put_preference()

    assert first.status == 200
    preference = FediversePreferences.get_by_actor(handle)
    refute FediversePreferences.allowed_remote?(
             preference,
             "https://sub.bad.example/users/bob",
             "https://sub.bad.example/inbox"
           )

    assert FediversePreferences.allowed_remote?(
             preference,
             "https://good.example/users/bob",
             "https://good.example/inbox"
           )

    stale = params(did, 20) |> signed(private_key) |> put_preference()
    assert stale.status == 409
  end

  test "allowlist requires both actor and inbox domains to be allowed" do
    preference = %FediversePreference{
      domain_policy: "allowlist",
      allowed_domains: ["social.example"],
      blocked_domains: [],
      blocked_actors: []
    }

    assert FediversePreferences.allowed_remote?(
             preference,
             "https://social.example/users/bob",
             "https://social.example/inbox"
           )

    refute FediversePreferences.allowed_remote?(
             preference,
             "https://social.example/users/bob",
             "https://other.example/inbox"
           )
  end
end
