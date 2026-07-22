defmodule AnsibleRelay.Repo.Migrations.AddPrivateBoardEncryption do
  use Ecto.Migration

  def change do
    alter table(:forum_host_boards) do
      add(:encryption_epoch, :bigint, null: false, default: 0)
      add(:encryption_state, :string, null: false, default: "disabled")
    end

    create table(:forum_host_board_device_keys, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :hosted_board_id,
        references(:forum_host_boards,
          column: :hosted_board_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:device_key_id, :string, null: false)
      add(:agreement_public_key_hex, :string, null: false)
      add(:public_key_hash, :string, null: false)
      add(:pairwise_subject_hash, :string, null: false)
      add(:device_signing_thumbprint, :string, null: false)
      add(:policy_version, :bigint, null: false)
      add(:state, :string, null: false, default: "active")
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:forum_host_board_device_keys, [:hosted_board_id, :device_key_id]))

    create(
      unique_index(:forum_host_board_device_keys, [:hosted_board_id, :public_key_hash])
    )

    create table(:forum_host_board_encryption_epochs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :hosted_board_id,
        references(:forum_host_boards,
          column: :hosted_board_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:epoch, :bigint, null: false)
      add(:policy_version, :bigint, null: false)
      add(:state, :string, null: false)
      add(:created_by_subject_hash, :string, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:forum_host_board_encryption_epochs, [:hosted_board_id, :epoch]))

    create table(:forum_host_board_epoch_envelopes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :epoch_id,
        references(:forum_host_board_encryption_epochs,
          type: :binary_id,
          on_delete: :delete_all
        ),
        null: false
      )

      add(
        :recipient_device_key_id,
        references(:forum_host_board_device_keys,
          column: :id,
          type: :binary_id,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:sender_public_key_hash, :string, null: false)
      add(:envelope, :map, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:forum_host_board_epoch_envelopes, [:epoch_id, :recipient_device_key_id]))
  end
end
