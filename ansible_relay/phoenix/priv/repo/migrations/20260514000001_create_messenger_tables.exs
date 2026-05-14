defmodule AnsibleRelay.Repo.Migrations.CreateMessengerTables do
  use Ecto.Migration

  def change do
    create table(:messenger_devices) do
      add(:subject_did, :string, null: false)
      add(:device_id, :string, null: false)
      add(:messenger_identity_key, :text, null: false)
      add(:signed_pre_key_id, :integer, null: false)
      add(:signed_pre_key, :text, null: false)
      add(:signed_pre_key_signature, :text, null: false)
      add(:expires_at, :string)
      add(:binding, :map, null: false, default: %{})
      add(:binding_signature, :text, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:messenger_devices, [:subject_did, :device_id],
        name: :messenger_devices_subject_device_index
      )
    )

    create(index(:messenger_devices, [:subject_did]))

    create table(:messenger_pre_keys) do
      add(:subject_did, :string, null: false)
      add(:device_id, :string, null: false)
      add(:pre_key_id, :integer, null: false)
      add(:pre_key, :text, null: false)
      add(:reserved_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:messenger_pre_keys, [:subject_did, :device_id, :pre_key_id],
        name: :messenger_pre_keys_device_key_index
      )
    )

    create(
      index(:messenger_pre_keys, [:subject_did, :device_id, :reserved_at, :pre_key_id],
        name: :messenger_pre_keys_reservation_index
      )
    )

    create table(:messenger_messages) do
      add(:message_id, :string, null: false)
      add(:sender_did, :string, null: false)
      add(:sender_device_id, :string, null: false)
      add(:recipient_did, :string, null: false)
      add(:recipient_device_id, :string, null: false)
      add(:ciphertext_type, :string, null: false)
      add(:ciphertext, :text, null: false)
      add(:protocol_version, :string, null: false)
      add(:message_created_at, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:messenger_messages, [:message_id], name: :messenger_messages_message_id_index)
    )

    create(
      index(:messenger_messages, [:recipient_device_id, :message_created_at],
        name: :messenger_messages_mailbox_index
      )
    )

    create table(:messenger_message_acks) do
      add(:message_id, :string, null: false)
      add(:recipient_device_id, :string, null: false)
      add(:acked_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:messenger_message_acks, [:message_id, :recipient_device_id],
        name: :messenger_message_acks_message_recipient_index
      )
    )
  end
end
