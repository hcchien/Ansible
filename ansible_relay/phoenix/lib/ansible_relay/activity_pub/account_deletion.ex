defmodule AnsibleRelay.ActivityPub.AccountDeletion do
  @moduledoc """
  Durable ActivityPub account deletion ceremony.

  Remote erasure is best-effort. The Relay first creates durable Delete
  delivery attempts, then hides the actor and removes follower edges.
  """

  alias AnsibleRelay.{
    Db.ActivityPubAccountDeletion,
    Db.ActivityPubDeliveryAttempt,
    FediversePreferences,
    Repo
  }

  alias AnsibleRelay.ActivityPub.{Actor, Inbox}

  def request(did, actor, reason_code, base_url) do
    Repo.transaction(fn ->
      preference = FediversePreferences.get_by_did(did)

      if is_nil(preference) do
        Repo.rollback(:fediverse_account_not_found)
      end

      followers =
        actor
        |> Inbox.followers()
        |> Enum.filter(fn follower ->
          FediversePreferences.allowed_remote?(
            preference,
            follower.remote_actor,
            follower.remote_inbox
          )
        end)
        |> Enum.uniq_by(& &1.remote_inbox)

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      actor_uri = Actor.actor_url(actor, base_url)

      delete = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{actor_uri}#delete",
        "type" => "Delete",
        "actor" => actor_uri,
        "object" => actor_uri,
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      Enum.each(followers, fn follower ->
        %ActivityPubDeliveryAttempt{}
        |> ActivityPubDeliveryAttempt.changeset(%{
          publication_id: "ap-account-delete:#{did}",
          remote_inbox: follower.remote_inbox,
          activity_id: delete["id"],
          activity_type: "Delete",
          payload: delete,
          status: "pending",
          attempt_count: 0
        })
        |> Repo.insert!(on_conflict: :nothing)
      end)

      preference
      |> AnsibleRelay.Db.FediversePreference.changeset(%{
        enabled: false,
        allow_remote_followers: false,
        revision: preference.revision + 1
      })
      |> Repo.update!()

      FediversePreferences.delete_followers_for_actor(actor)

      deletion =
        %ActivityPubAccountDeletion{}
        |> ActivityPubAccountDeletion.changeset(%{
          did: did,
          actor: actor,
          reason_code: reason_code,
          follower_count: length(followers),
          requested_at: now
        })
        |> Repo.insert!(
          on_conflict:
            {:replace, [:actor, :reason_code, :follower_count, :requested_at, :updated_at]},
          conflict_target: :did
        )

      %{deletion: deletion, deliveries: length(followers)}
    end)
  end
end
