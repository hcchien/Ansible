defmodule AnsibleRelay.Repo.Migrations.CreateDevicePushTokens do
  use Ecto.Migration

  def change do
    create table(:device_push_tokens) do
      add(:subject_did, :string, null: false)
      add(:device_id, :string, null: false)
      add(:push_token, :text, null: false)
      add(:platform, :string, null: false)
      add(:categories, {:array, :string}, null: false, default: [])

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:device_push_tokens, [:subject_did, :device_id],
        name: :device_push_tokens_subject_device_index
      )
    )

    create(index(:device_push_tokens, [:subject_did]))
  end
end
