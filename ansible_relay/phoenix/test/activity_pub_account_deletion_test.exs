defmodule AnsibleRelay.ActivityPub.AccountDeletionTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.ActivityPub.{AccountDeletion, Inbox}

  alias AnsibleRelay.Db.{
    ActivityPubAccountDeletion,
    ActivityPubDeliveryAttempt,
    ActivityPubFollower,
    FediversePreference
  }

  alias AnsibleRelay.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "queues Delete durably before disabling actor and removing follower edges" do
    did = "did:elix:delete-test"
    actor = "alice"

    Repo.insert!(%FediversePreference{
      did: did,
      actor: actor,
      enabled: true,
      allow_remote_followers: true,
      revision: 7,
      signature: String.duplicate("a", 128),
      signature_scheme: "ed25519"
    })

    Repo.insert!(%ActivityPubFollower{
      actor: actor,
      remote_actor: "https://mastodon.example/users/bob",
      remote_inbox: "https://mastodon.example/inbox"
    })

    assert {:ok, %{deliveries: 1}} =
             AccountDeletion.request(
               did,
               actor,
               "user_requested",
               "https://relay.elix.cool"
             )

    assert Inbox.followers(actor) == []
    preference = Repo.get_by!(FediversePreference, did: did)
    refute preference.enabled
    refute preference.allow_remote_followers
    assert preference.revision == 8

    attempt = Repo.one!(ActivityPubDeliveryAttempt)
    assert attempt.activity_type == "Delete"
    assert attempt.payload["object"] == "https://relay.elix.cool/users/alice"
    assert attempt.status == "pending"

    audit = Repo.get_by!(ActivityPubAccountDeletion, did: did)
    assert audit.reason_code == "user_requested"
    assert audit.follower_count == 1
  end
end
