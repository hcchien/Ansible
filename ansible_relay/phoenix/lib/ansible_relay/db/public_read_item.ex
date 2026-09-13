defmodule AnsibleRelay.Db.PublicReadItem do
  @moduledoc "Read-only latest-revision view over the Relay's accepted operation log."
  use Ecto.Schema
  @primary_key {:log_id, :integer, autogenerate: false}
  schema "relay_read_items" do
    field(:op_id, :string)
    field(:author_did, :string)
    field(:entity_type, :string)
    field(:entity_id, :string)
    field(:op_type, :string)
    field(:signed_payload, :string)
    field(:payload, :map)
    field(:signature, :string)
    field(:schema_version, :integer)
    field(:received_at, :utc_datetime_usec)
  end
end
