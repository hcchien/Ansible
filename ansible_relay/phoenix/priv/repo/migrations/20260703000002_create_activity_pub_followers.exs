defmodule AnsibleRelay.Repo.Migrations.CreateActivityPubFollowers do
  @moduledoc """
  Inbound ActivityPub Follow state (Phase 4 partial completion): remote
  actors following a local AP actor mirror. Social edges on the AP mirror
  only — never trust-bearing for native surfaces.
  """

  use Ecto.Migration

  def change do
    create table(:activity_pub_followers) do
      add(:actor, :string, null: false)
      add(:remote_actor, :string, null: false)
      add(:remote_inbox, :string, null: false)
      add(:follow_activity_id, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:activity_pub_followers, [:actor, :remote_actor],
        name: :activity_pub_followers_actor_remote_index
      )
    )
  end
end
