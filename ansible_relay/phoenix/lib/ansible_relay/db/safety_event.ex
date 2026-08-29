defmodule AnsibleRelay.Db.SafetyEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @event_types ~w(report_content block_user)
  @target_kinds ~w(user profile thread post content comment)
  @statuses ~w(open actioned dismissed)

  @derive {Jason.Encoder,
           only: [
             :id,
             :event_type,
             :reporter_did,
             :subject_did,
             :target_kind,
             :target_ref,
             :reason_code,
             :status,
             :inserted_at
           ]}
  schema "safety_events" do
    field(:event_type, :string)
    field(:reporter_did, :string)
    field(:subject_did, :string)
    field(:target_kind, :string)
    field(:target_ref, :string)
    field(:reason_code, :string)
    field(:note, :string)
    field(:status, :string, default: "open")

    timestamps(type: :utc_datetime_usec)
  end

  def event_types, do: @event_types
  def target_kinds, do: @target_kinds

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_type,
      :reporter_did,
      :subject_did,
      :target_kind,
      :target_ref,
      :reason_code,
      :note,
      :status
    ])
    |> validate_required([:event_type, :reporter_did, :target_kind, :target_ref, :reason_code])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:target_kind, @target_kinds)
    |> validate_inclusion(:reason_code, AnsibleRelay.ForumHost.ReportReason.codes())
    |> validate_inclusion(:status, @statuses)
    |> validate_subject_for_block()
    |> unique_constraint([:reporter_did, :event_type, :target_kind, :target_ref],
      name: :safety_events_open_dedup_index
    )
  end

  defp validate_subject_for_block(changeset) do
    if get_field(changeset, :event_type) == "block_user" do
      validate_required(changeset, [:subject_did])
    else
      changeset
    end
  end
end
