defmodule AnsibleRelay.Repo.Migrations.CreateActivityPubInboundSecurity do
  use Ecto.Migration

  def change do
    create table(:activity_pub_inbound_receipts) do
      add(:signature_hash, :string, null: false)
      add(:actor_uri, :string, null: false)
      add(:key_id, :string, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:activity_pub_inbound_receipts, [:signature_hash]))
    create(index(:activity_pub_inbound_receipts, [:expires_at]))

    create table(:activity_pub_inbound_activities) do
      add(:activity_id, :string, null: false)
      add(:local_actor, :string, null: false)
      add(:remote_actor, :string, null: false)
      add(:activity_type, :string, null: false)
      add(:object_id, :string)
      add(:payload, :map, null: false)
      add(:received_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:activity_pub_inbound_activities, [:activity_id]))
    create(index(:activity_pub_inbound_activities, [:id]))
    create(index(:activity_pub_inbound_activities, [:remote_actor]))

    create table(:activity_pub_account_deletions) do
      add(:did, :string, null: false)
      add(:actor, :string, null: false)
      add(:reason_code, :string, null: false, default: "user_requested")
      add(:follower_count, :integer, null: false, default: 0)
      add(:requested_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:activity_pub_account_deletions, [:did]))
  end
end
