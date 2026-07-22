defmodule AnsibleRelay.Db.ForumHostBoardDpopProof do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:proof_hash, :string, autogenerate: false}
  schema "forum_host_board_dpop_proofs" do
    field(:capability_hash, :string)
    field(:expires_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(proof, attrs) do
    proof
    |> cast(attrs, [:proof_hash, :capability_hash, :expires_at])
    |> validate_required([:proof_hash, :capability_hash, :expires_at])
  end
end
