defmodule AnsibleRelay.Db.IdentityAccountFreeze do
  @moduledoc """
  A frozen account: a veto over a pending recovery anchor halts all
  automatic re-anchoring for the DID until manual/issuer-assisted
  resolution (design §Re-Anchor Protocol, hijack resistance — silent
  account takeover is an irreversible identity harm, conflict-priority #1).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:did, :string, autogenerate: false}
  schema "identity_account_freezes" do
    field(:reason, :string, default: "veto")
    field(:vetoed_anchor_cid, :string)
    field(:frozen_at, :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:did, :reason, :vetoed_anchor_cid, :frozen_at])
    |> validate_required([:did, :reason, :frozen_at])
  end
end
