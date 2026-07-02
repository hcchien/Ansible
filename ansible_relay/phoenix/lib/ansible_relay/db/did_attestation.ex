defmodule AnsibleRelay.Db.DidAttestation do
  @moduledoc """
  The accepted issuer-signed VC for a DID (portable issuer re-verification
  layer). One row per DID — a newer successful presentation replaces the old
  one. The `vc` column stores the credential exactly as presented so its
  issuer proof stays verifiable byte-for-byte.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:did, :string, autogenerate: false}
  schema "did_attestations" do
    field(:credential_type, :string)
    field(:reputation_tier, :string)
    field(:vc, :map)
    field(:presented_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(did credential_type reputation_tier vc presented_at)a

  def changeset(attestation, attrs) do
    attestation
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end
end
