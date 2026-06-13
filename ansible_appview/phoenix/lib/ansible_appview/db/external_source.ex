defmodule AnsibleAppview.Db.ExternalSource do
  @moduledoc """
  A curated remote ActivityPub actor we pull public outbox content from.

  This is the allowlist at the heart of the inbound-federation design: only
  actors with an enabled row here are ever fetched, and removing/disabling a row
  is the reversibility lever (Constitution Base Rule 7). `compliance_level` is an
  assessment of the *origin instance* (`"compatible"` once reviewed, else
  `"unknown"`) and is surfaced with the content — it never grants Elix trust.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @compliance_levels ~w(compatible unknown)

  schema "external_sources" do
    field(:actor_uri, :string)
    field(:instance, :string)
    field(:display_name, :string)
    field(:compliance_level, :string, default: "unknown")
    field(:enabled, :boolean, default: true)
    field(:last_polled_at, :utc_datetime_usec)
    # The Elix board this source's content surfaces in (design D4, Task 4b-1).
    # NULL = ingested but not surfaced to any board. Ingest stamps this onto the
    # external feed_items rows so per-board reads are a simple filter.
    field(:board_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(actor_uri instance display_name compliance_level enabled last_polled_at board_id)a
  @required ~w(actor_uri instance)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:compliance_level, @compliance_levels)
    |> unique_constraint(:actor_uri, name: :external_sources_actor_uri_index)
  end

  @doc "Allowed `compliance_level` values."
  def compliance_levels, do: @compliance_levels
end
