defmodule AnsibleRelay.Repo.Migrations.AddBoardAccessGrants do
  use Ecto.Migration

  def change do
    create table(:forum_host_board_policy_versions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:policy_hash, :string, null: false)

      add(
        :hosted_board_id,
        references(:forum_host_boards,
          column: :hosted_board_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:version, :bigint, null: false)
      add(:canonical_policy, :map, null: false)
      add(:actor_did, :string, null: false)
      add(:approvals, :map, null: false, default: %{})
      add(:effective_at, :utc_datetime_usec, null: false)
      add(:superseded_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:forum_host_board_policy_versions, [:hosted_board_id, :version]))

    create(unique_index(:forum_host_board_policy_versions, [:hosted_board_id, :policy_hash]))

    create table(:forum_host_verification_nonces, primary_key: false) do
      add(:nonce_hash, :string, primary_key: true)
      add(:state_hash, :string, null: false)

      add(
        :hosted_board_id,
        references(:forum_host_boards,
          column: :hosted_board_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:audience, :string, null: false)
      add(:policy_version, :bigint, null: false)
      add(:action, :string, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:consumed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:forum_host_verification_nonces, [:hosted_board_id, :expires_at]))

    create table(:forum_host_board_access_grants, primary_key: false) do
      add(:capability_hash, :string, primary_key: true)

      add(
        :hosted_board_id,
        references(:forum_host_boards,
          column: :hosted_board_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:pairwise_subject_hash, :string, null: false)
      add(:device_key_thumbprint, :string, null: false)
      add(:audience, :string, null: false)
      add(:policy_version, :bigint, null: false)
      add(:scopes, {:array, :string}, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
      add(:revocation_reason, :string)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:forum_host_board_access_grants, [:hosted_board_id, :expires_at]))
    create(index(:forum_host_board_access_grants, [:pairwise_subject_hash, :expires_at]))

    create table(:forum_host_board_dpop_proofs, primary_key: false) do
      add(:proof_hash, :string, primary_key: true)

      add(
        :capability_hash,
        references(:forum_host_board_access_grants,
          column: :capability_hash,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:expires_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:forum_host_board_dpop_proofs, [:expires_at]))
  end
end
