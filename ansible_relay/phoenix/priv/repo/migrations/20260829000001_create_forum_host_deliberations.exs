defmodule AnsibleRelay.Repo.Migrations.CreateForumHostDeliberations do
  use Ecto.Migration

  def change do
    create table(:forum_host_deliberations, primary_key: false) do
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

      add(:creator_did, :string, null: false)
      add(:last_intent_id, :string, null: false)
      add(:title, :string, null: false)
      add(:prompt, :text, null: false)
      add(:context, :text)
      add(:status, :string, null: false, default: "collecting")
      add(:statement_attribution, :string, null: false, default: "host_pseudonymous")
      add(:export_mode, :string, null: false, default: "aggregates_only")
      add(:min_report_participants, :integer, null: false, default: 15)
      add(:min_group_size, :integer, null: false, default: 5)
      add(:access_policy_version, :bigint, null: false)
      add(:closes_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forum_host_deliberations, [:hosted_board_id, :inserted_at]))
    create(unique_index(:forum_host_deliberations, [:last_intent_id]))

    create(
      constraint(:forum_host_deliberations, :forum_host_deliberations_status_check,
        check: "status IN ('collecting', 'frozen', 'published', 'archived')"
      )
    )

    create(
      constraint(:forum_host_deliberations, :forum_host_deliberations_export_mode_check,
        check: "export_mode IN ('no_external_analysis', 'aggregates_only', 'pseudonymous_matrix')"
      )
    )

    create table(:forum_host_deliberation_statements, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :deliberation_id,
        references(:forum_host_deliberations, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:author_did, :string, null: false)
      add(:author_participant_key, :string, null: false)
      add(:text, :text, null: false)
      add(:state, :string, null: false, default: "accepted")
      add(:moderation_reason_code, :string)
      add(:last_intent_id, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:forum_host_deliberation_statements, [:deliberation_id, :inserted_at]))
    create(unique_index(:forum_host_deliberation_statements, [:last_intent_id]))

    create(
      constraint(
        :forum_host_deliberation_statements,
        :forum_host_deliberation_statement_state_check,
        check: "state IN ('pending', 'accepted', 'rejected', 'withdrawn')"
      )
    )

    create table(:forum_host_deliberation_votes) do
      add(
        :deliberation_id,
        references(:forum_host_deliberations, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(
        :statement_id,
        references(:forum_host_deliberation_statements, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:participant_key, :string, null: false)
      add(:stance, :string, null: false)
      add(:last_intent_id, :string, null: false)
      add(:access_policy_version, :bigint, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :forum_host_deliberation_votes,
        [:deliberation_id, :statement_id, :participant_key],
        name: :forum_host_deliberation_votes_participant_statement_index
      )
    )

    create(unique_index(:forum_host_deliberation_votes, [:last_intent_id]))
    create(index(:forum_host_deliberation_votes, [:deliberation_id, :stance]))

    create(
      constraint(:forum_host_deliberation_votes, :forum_host_deliberation_vote_stance_check,
        check: "stance IN ('agree', 'disagree', 'pass')"
      )
    )

    create table(:forum_host_deliberation_analysis_snapshots, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :deliberation_id,
        references(:forum_host_deliberations, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:dataset_digest, :string, null: false)
      add(:algorithm, :string, null: false)
      add(:algorithm_version, :string, null: false)
      add(:seed, :bigint, null: false)
      add(:parameters, :map, null: false, default: %{})
      add(:result, :map, null: false, default: %{})
      add(:status, :string, null: false, default: "complete")
      add(:generated_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :forum_host_deliberation_analysis_snapshots,
        [:deliberation_id, :dataset_digest, :algorithm_version],
        name: :forum_host_deliberation_snapshots_dataset_version_index
      )
    )

    create(index(:forum_host_deliberation_analysis_snapshots, [:deliberation_id, :generated_at]))
  end
end
