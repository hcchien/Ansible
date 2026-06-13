defmodule AnsibleRelay.Repo.Migrations.CreateIdentityAnchors do
  use Ecto.Migration

  @moduledoc """
  Task 4 (relay) — self-certifying identity anchor chain store.

  Persists the user-signed anchor chain keyed by (did, anchor_cid). The
  relay STORES and SERVES these objects but does not own them: a different
  relay could verify the same chain (design §"Anchor as a Self-Certifying
  Object"). The `did_accounts` row becomes a cache of the active anchor.
  """

  def change do
    create table(:identity_anchors, primary_key: false) do
      add(:did, :string, null: false)
      add(:anchor_cid, :string, null: false)
      add(:prev_anchor_cid, :string)
      add(:reason, :string, null: false)
      add(:identity_key, :string, null: false)
      add(:handle, :string, null: false)
      add(:custody_class, :string, null: false, default: "software")
      add(:schema_version, :integer, null: false, default: 1)
      add(:devices, :map, null: false, default: %{})
      add(:sig, :string, null: false)
      add(:device_sig, :string)
      # Full canonical body JSON exactly as signed/hashed — preserved so the
      # chain stays independently verifiable (self-certifying).
      add(:canonical_body, :text, null: false)
      # active | pending | vetoed | superseded
      add(:state, :string, null: false, default: "pending")
      # Set for recovery anchors held during the hijack-resistance grace window.
      add(:grace_until, :utc_datetime_usec)

      add(:created_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:identity_anchors, [:did, :anchor_cid]))
    create(index(:identity_anchors, [:did, :state]))
    # At most one active anchor per DID (the cache invariant).
    create(
      unique_index(:identity_anchors, [:did],
        where: "state = 'active'",
        name: :identity_anchors_one_active_per_did
      )
    )

    # An account frozen by a veto: subsequent auto re-anchors are rejected
    # (423 Locked) until manual/issuer-assisted resolution.
    create table(:identity_account_freezes, primary_key: false) do
      add(:did, :string, primary_key: true)
      add(:reason, :string, null: false, default: "veto")
      add(:vetoed_anchor_cid, :string)
      add(:frozen_at, :utc_datetime_usec, null: false)
    end
  end
end
