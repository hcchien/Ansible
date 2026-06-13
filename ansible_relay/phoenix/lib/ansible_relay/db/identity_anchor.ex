defmodule AnsibleRelay.Db.IdentityAnchor do
  @moduledoc """
  A persisted node of a user's self-certifying identity anchor chain
  (design §"Anchor as a Self-Certifying Object"). Keyed by (did, anchor_cid).

  The relay stores and serves these; it does not own them. `canonical_body`
  holds the exact bytes that were hashed to `anchor_cid` and signed by
  `identity_key`, so any relay can re-verify the chain independently.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]
  schema "identity_anchors" do
    field(:did, :string)
    field(:anchor_cid, :string)
    field(:prev_anchor_cid, :string)
    field(:reason, :string)
    field(:identity_key, :string)
    field(:handle, :string)
    field(:custody_class, :string, default: "software")
    field(:schema_version, :integer, default: 1)
    field(:devices, :map, default: %{})
    field(:sig, :string)
    field(:device_sig, :string)
    field(:canonical_body, :string)
    field(:state, :string, default: "pending")
    field(:grace_until, :utc_datetime_usec)
    field(:created_at, :utc_datetime_usec)

    timestamps()
  end

  @castable ~w(did anchor_cid prev_anchor_cid reason identity_key handle
               custody_class schema_version devices sig device_sig
               canonical_body state grace_until created_at)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @castable)
    |> validate_required([
      :did,
      :anchor_cid,
      :reason,
      :identity_key,
      :handle,
      :sig,
      :canonical_body,
      :state,
      :created_at
    ])
    |> validate_inclusion(:reason, ~w(initial rotation recovery device_change))
    |> validate_inclusion(:state, ~w(active pending vetoed superseded))
    |> unique_constraint([:did, :anchor_cid])
  end
end
