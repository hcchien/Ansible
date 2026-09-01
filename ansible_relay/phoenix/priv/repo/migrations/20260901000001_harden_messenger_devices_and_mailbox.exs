defmodule AnsibleRelay.Repo.Migrations.HardenMessengerDevicesAndMailbox do
  use Ecto.Migration

  def change do
    alter table(:messenger_devices) do
      add(:revoked_at, :utc_datetime_usec)
      add(:revocation_reason, :string)
    end


    alter table(:messenger_messages) do
      add(:expires_at, :utc_datetime_usec)
    end

    execute(
      "UPDATE messenger_messages SET expires_at = inserted_at + INTERVAL '30 days' WHERE expires_at IS NULL",
      "UPDATE messenger_messages SET expires_at = NULL"
    )

    alter table(:messenger_messages) do
      modify(:expires_at, :utc_datetime_usec, null: false)
    end

    create(
      index(:messenger_devices, [:subject_did, :revoked_at],
        name: :messenger_devices_active_subject_index
      )
    )

    create(
      index(:messenger_messages, [:recipient_did, :recipient_device_id, :id],
        name: :messenger_messages_mailbox_cursor_index
      )
    )

    create(index(:messenger_messages, [:expires_at]))
  end
end
