defmodule AnsibleRelay.Db.ForumHostDeliberationAnalysisSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "forum_host_deliberation_analysis_snapshots" do
    field(:deliberation_id, :binary_id)
    field(:dataset_digest, :string)
    field(:algorithm, :string)
    field(:algorithm_version, :string)
    field(:seed, :integer)
    field(:parameters, :map, default: %{})
    field(:result, :map, default: %{})
    field(:status, :string, default: "complete")
    field(:generated_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :deliberation_id,
      :dataset_digest,
      :algorithm,
      :algorithm_version,
      :seed,
      :parameters,
      :result,
      :status,
      :generated_at
    ])
    |> validate_required([
      :deliberation_id,
      :dataset_digest,
      :algorithm,
      :algorithm_version,
      :seed,
      :parameters,
      :result,
      :status,
      :generated_at
    ])
    |> unique_constraint([:deliberation_id, :dataset_digest, :algorithm_version],
      name: :forum_host_deliberation_snapshots_dataset_version_index
    )
  end
end
