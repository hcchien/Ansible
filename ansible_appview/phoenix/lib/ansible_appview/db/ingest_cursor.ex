defmodule AnsibleAppview.Db.IngestCursor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:source, :string, autogenerate: false}
  schema "ingest_cursors" do
    field :cursor, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:source, :cursor])
    |> validate_required([:source, :cursor])
  end
end
