defmodule AnsibleRelay.Db.ForumHostReport do
  use Ecto.Schema
  import Ecto.Changeset

  @target_kinds ~w(post thread)
  @statuses ~w(open actioned dismissed)

  # `note` is included because reports are only ever serialized back to the
  # reporter and to board moderators; public surfaces (moderation-state,
  # tombstones) never serialize reports.
  @derive {Jason.Encoder,
           only: [
             :id,
             :target_kind,
             :target_ref,
             :board_id,
             :reporter_did,
             :reason_code,
             :note,
             :status,
             :inserted_at
           ]}
  schema "forum_host_reports" do
    field(:target_kind, :string)
    field(:target_ref, :string)
    field(:board_id, :string)
    field(:reporter_did, :string)
    field(:reason_code, :string)
    field(:note, :string)
    field(:status, :string, default: "open")

    timestamps(type: :utc_datetime_usec)
  end

  def target_kinds, do: @target_kinds
  def statuses, do: @statuses

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :target_kind,
      :target_ref,
      :board_id,
      :reporter_did,
      :reason_code,
      :note,
      :status
    ])
    |> validate_required([:target_kind, :target_ref, :board_id, :reporter_did, :reason_code])
    |> validate_inclusion(:target_kind, @target_kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:reason_code, AnsibleRelay.ForumHost.ReportReason.codes())
    |> unique_constraint([:reporter_did, :target_kind, :target_ref],
      name: :forum_host_reports_open_dedup_index
    )
  end
end
