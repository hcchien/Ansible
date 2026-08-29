defmodule AnsibleRelay.Db.ForumHostDeliberation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "forum_host_deliberations" do
    field(:hosted_board_id, :string)
    field(:creator_did, :string)
    field(:last_intent_id, :string)
    field(:title, :string)
    field(:prompt, :string)
    field(:context, :string)
    field(:status, :string, default: "collecting")
    field(:statement_attribution, :string, default: "host_pseudonymous")
    field(:export_mode, :string, default: "aggregates_only")
    field(:min_report_participants, :integer, default: 15)
    field(:min_group_size, :integer, default: 5)
    field(:access_policy_version, :integer)
    field(:closes_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(deliberation, attrs) do
    deliberation
    |> cast(attrs, [
      :hosted_board_id,
      :creator_did,
      :last_intent_id,
      :title,
      :prompt,
      :context,
      :status,
      :statement_attribution,
      :export_mode,
      :min_report_participants,
      :min_group_size,
      :access_policy_version,
      :closes_at
    ])
    |> validate_required([
      :hosted_board_id,
      :creator_did,
      :last_intent_id,
      :title,
      :prompt,
      :status,
      :statement_attribution,
      :export_mode,
      :min_report_participants,
      :min_group_size,
      :access_policy_version
    ])
    |> update_change(:title, &String.trim/1)
    |> update_change(:prompt, &String.trim/1)
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:prompt, min: 1, max: 2_000)
    |> validate_length(:context, max: 8_000)
    |> validate_inclusion(:status, ~w(collecting frozen published archived))
    |> validate_inclusion(:statement_attribution, ~w(host_pseudonymous))
    |> validate_inclusion(
      :export_mode,
      ~w(no_external_analysis aggregates_only pseudonymous_matrix)
    )
    |> validate_number(:min_report_participants,
      greater_than_or_equal_to: 5,
      less_than_or_equal_to: 10_000
    )
    |> validate_number(:min_group_size, greater_than_or_equal_to: 3, less_than_or_equal_to: 1_000)
    |> unique_constraint(:last_intent_id)
  end
end
