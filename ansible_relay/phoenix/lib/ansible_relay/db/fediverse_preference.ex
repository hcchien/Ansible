defmodule AnsibleRelay.Db.FediversePreference do
  use Ecto.Schema
  import Ecto.Changeset

  schema "fediverse_preferences" do
    field(:did, :string)
    field(:actor, :string)
    field(:enabled, :boolean, default: false)
    field(:default_note_visibility, :string, default: "public")
    field(:allow_remote_followers, :boolean, default: true)
    field(:domain_policy, :string, default: "open")
    field(:allowed_domains, {:array, :string}, default: [])
    field(:blocked_domains, {:array, :string}, default: [])
    field(:blocked_actors, {:array, :string}, default: [])
    field(:revision, :integer)
    field(:signature, :string)
    field(:signature_scheme, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :did,
      :actor,
      :enabled,
      :default_note_visibility,
      :allow_remote_followers,
      :domain_policy,
      :allowed_domains,
      :blocked_domains,
      :blocked_actors,
      :revision,
      :signature,
      :signature_scheme
    ])
    |> validate_required([
      :did,
      :actor,
      :enabled,
      :default_note_visibility,
      :allow_remote_followers,
      :domain_policy,
      :revision,
      :signature,
      :signature_scheme
    ])
    |> validate_inclusion(:default_note_visibility, ["public", "unlisted"])
    |> validate_inclusion(:domain_policy, ["open", "allowlist"])
    |> validate_number(:revision, greater_than: 0)
    |> unique_constraint(:did)
    |> unique_constraint(:actor)
  end
end

