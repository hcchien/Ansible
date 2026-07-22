defmodule AnsibleRelay.Repo.Migrations.AddIdentitySigningAlgorithm do
  use Ecto.Migration

  def change do
    alter table(:did_accounts) do
      add(:signing_algorithm, :string, null: false, default: "ed25519")
      add(:key_version, :bigint, null: false, default: 1)
    end

    alter table(:verified_dids) do
      add(:signing_algorithm, :string, null: false, default: "ed25519")
      add(:key_version, :bigint, null: false, default: 1)
    end

    alter table(:identity_anchors) do
      add(:identity_key_algorithm, :string, null: false, default: "ed25519")
    end

    create(
      constraint(:did_accounts, :did_accounts_signing_algorithm,
        check: "signing_algorithm IN ('ed25519', 'p256-sha256')"
      )
    )

    create(
      constraint(:verified_dids, :verified_dids_signing_algorithm,
        check: "signing_algorithm IN ('ed25519', 'p256-sha256')"
      )
    )

    create(
      constraint(:identity_anchors, :identity_anchors_signing_algorithm,
        check: "identity_key_algorithm IN ('ed25519', 'p256-sha256')"
      )
    )

    create(
      constraint(:did_accounts, :did_accounts_key_version_positive, check: "key_version > 0")
    )

    create(
      constraint(:verified_dids, :verified_dids_key_version_positive, check: "key_version > 0")
    )
  end
end
