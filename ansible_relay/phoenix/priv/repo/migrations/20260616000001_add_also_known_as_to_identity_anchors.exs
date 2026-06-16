defmodule AnsibleRelay.Repo.Migrations.AddAlsoKnownAsToIdentityAnchors do
  use Ecto.Migration

  @moduledoc """
  Layered identity (2026-06-16): `also_known_as` joins the signed anchor body
  (at://handle, did:key, optional did:plc). Stored so the served anchor object
  stays consistent with the persisted `canonical_body`.
  """

  def change do
    alter table(:identity_anchors) do
      add(:also_known_as, {:array, :string}, null: false, default: [])
    end
  end
end
