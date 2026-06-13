defmodule AnsibleRelay.Repo.Migrations.CreateOpSnapshots do
  use Ecto.Migration

  # Phase 2 (service architecture plan §Phase 2.3) — signed snapshot format.
  #
  # A snapshot is a content-addressed, relay-signed summary of op state up to a
  # `cursor` (an inclusive `ops.id` log_id). A consumer rebuilds its read model
  # by folding the snapshot then applying the delta of ops after `cursor`,
  # instead of replaying the full op history.
  #
  # DESIGN TODO (plan §Phase 2.3): physical time-based PARTITIONING of the `ops`
  # table is deliberately deferred — it is a risky live-table migration. The
  # snapshot/retention mechanism here is partition-agnostic: it folds and prunes
  # by `ops.id` ranges, which remain valid whether or not `ops` is later
  # partitioned. Revisit partitioning as its own slice.
  def change do
    create table(:op_snapshots) do
      # Inclusive log_id (ops.id) the snapshot covers up to. A consumer applies
      # /api/v1/ops/delta?cursor=<cursor> afterwards.
      add(:cursor, :bigint, null: false)
      # Content address: sha256 over the canonical snapshot body (digest +
      # cursor + op_count + created_at). Used as the stable snapshot identity.
      add(:snapshot_cid, :string, null: false)
      # Deterministic digest over the included ops (sha256 of sorted op_id|op_cid
      # lines). Recomputable by a consumer from the op set to detect tampering.
      add(:digest, :string, null: false)
      # Number of ops covered (cursor range 1..cursor, minus any gaps).
      add(:op_count, :bigint, null: false)
      # Ed25519 signature (hex) by the relay snapshot key over the snapshot_cid.
      add(:signature, :string, null: false)
      # Hex Ed25519 public key the signature verifies against (pinned for audit
      # so a key rotation does not invalidate already-published snapshots).
      add(:signing_public_key_hex, :string, null: false)
      add(:created_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:op_snapshots, [:snapshot_cid], name: :op_snapshots_cid_index))
    create(index(:op_snapshots, [:cursor]))
  end
end
