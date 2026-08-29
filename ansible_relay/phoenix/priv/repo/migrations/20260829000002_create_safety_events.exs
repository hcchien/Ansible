defmodule AnsibleRelay.Repo.Migrations.CreateSafetyEvents do
  use Ecto.Migration

  def change do
    create table(:safety_events) do
      add(:event_type, :string, null: false)
      add(:reporter_did, :string, null: false)
      add(:subject_did, :string)
      add(:target_kind, :string, null: false)
      add(:target_ref, :string, null: false)
      add(:reason_code, :string, null: false)
      add(:note, :text)
      add(:status, :string, null: false, default: "open")

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:safety_events, [:status, :inserted_at]))
    create(index(:safety_events, [:subject_did, :status]))

    create(
      unique_index(
        :safety_events,
        [:reporter_did, :event_type, :target_kind, :target_ref],
        where: "status = 'open'",
        name: :safety_events_open_dedup_index
      )
    )
  end
end
