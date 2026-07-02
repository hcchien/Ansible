defmodule AnsibleRelay.Repo.Migrations.CreateDidAttestations do
  @moduledoc """
  Portable issuer re-verification layer (federation trust): persist the
  accepted issuer-signed VC per DID so any consumer (app, peer relay) can
  fetch it and re-verify the ISSUER proof itself instead of trusting a
  relay-asserted reputation tier.
  """

  use Ecto.Migration

  def change do
    create table(:did_attestations, primary_key: false) do
      add(:did, :string, primary_key: true)
      add(:credential_type, :string, null: false)
      add(:reputation_tier, :string, null: false)
      # The full issuer-signed VC exactly as presented (proof included) —
      # re-serializing could break the issuer signature's canonical form.
      add(:vc, :map, null: false)
      add(:presented_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
