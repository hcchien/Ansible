defmodule AnsibleRelay.Repo.Migrations.CreateActivityPubDeliveryAttempts do
  use Ecto.Migration

  def change do
    create table(:activity_pub_delivery_attempts) do
      add(:publication_id, :string, null: false)
      add(:remote_inbox, :string, null: false)
      add(:activity_id, :string, null: false)
      add(:activity_type, :string, null: false)
      add(:payload, :map, null: false)
      add(:status, :string, null: false)
      add(:attempt_count, :integer, null: false, default: 0)
      add(:last_attempt_at, :utc_datetime_usec)
      add(:next_retry_at, :utc_datetime_usec)
      add(:last_error, :text)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:activity_pub_delivery_attempts, [:publication_id, :remote_inbox],
        name: :activity_pub_delivery_attempts_publication_inbox_index
      )
    )

    create(index(:activity_pub_delivery_attempts, [:status]))
    create(index(:activity_pub_delivery_attempts, [:next_retry_at]))
  end
end
