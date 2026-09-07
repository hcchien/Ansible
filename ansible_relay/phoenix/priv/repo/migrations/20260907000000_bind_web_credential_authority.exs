defmodule AnsibleRelay.Repo.Migrations.BindWebCredentialAuthority do
  use Ecto.Migration

  def change do
    alter table(:webauthn_credentials) do
      add(:delegation, :map)
      add(:registration_attestation, :text)
    end
  end
end
