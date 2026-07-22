defmodule AnsibleRelay.Db.IdentityRecoveryAuditEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]
  schema "identity_recovery_audit_events" do
    field(:did, :string)
    field(:event_type, :string)
    field(:reason_code, :string)
    field(:anchor_cid, :string)
    field(:metadata, :map, default: %{})
    timestamps(updated_at: false)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:did, :event_type, :reason_code, :anchor_cid, :metadata])
    |> validate_required([:did, :event_type, :reason_code])
  end
end
