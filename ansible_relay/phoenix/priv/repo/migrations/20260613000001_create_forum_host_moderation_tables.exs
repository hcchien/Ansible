defmodule AnsibleRelay.Repo.Migrations.CreateForumHostModerationTables do
  use Ecto.Migration

  def change do
    create table(:forum_host_reports) do
      add(:target_kind, :string, null: false)
      add(:target_ref, :string, null: false)
      add(:board_id, :string, null: false)
      add(:reporter_did, :string, null: false)
      add(:reason_code, :string, null: false)
      add(:note, :text)
      add(:status, :string, null: false, default: "open")

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forum_host_reports, [:board_id, :status]))
    create(index(:forum_host_reports, [:target_ref]))

    # Duplicate collapse: one OPEN report per reporter + target. Resolved
    # (actioned/dismissed) reports do not block a fresh report.
    create(
      unique_index(:forum_host_reports, [:reporter_did, :target_kind, :target_ref],
        where: "status = 'open'",
        name: :forum_host_reports_open_dedup_index
      )
    )

    # Audit trail (constitution Base Rules 6/7): every moderation action is
    # time-stamped, attributed to a moderator DID, and reason-coded.
    create table(:forum_host_moderation_actions) do
      add(:action, :string, null: false)
      add(:target_ref, :string, null: false)
      add(:board_id, :string, null: false)
      add(:moderator_did, :string, null: false)
      add(:reason_code, :string, null: false)
      add(:report_id, references(:forum_host_reports, on_delete: :nilify_all))

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forum_host_moderation_actions, [:board_id]))
    create(index(:forum_host_moderation_actions, [:target_ref, :action]))
  end
end
