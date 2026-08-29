defmodule AnsibleRelay.Db.ForumHostModerationAction do
  use Ecto.Schema
  import Ecto.Changeset

  @actions ~w(dismiss_report remove_post_from_board lock_thread unlock_thread hide_context_note)

  @derive {Jason.Encoder,
           only: [
             :id,
             :action,
             :target_ref,
             :board_id,
             :moderator_did,
             :reason_code,
             :report_id,
             :inserted_at
           ]}
  schema "forum_host_moderation_actions" do
    field(:action, :string)
    field(:target_ref, :string)
    field(:board_id, :string)
    field(:moderator_did, :string)
    field(:reason_code, :string)
    field(:report_id, :integer)

    timestamps(type: :utc_datetime_usec)
  end

  def actions, do: @actions

  def changeset(action, attrs) do
    action
    |> cast(attrs, [:action, :target_ref, :board_id, :moderator_did, :reason_code, :report_id])
    |> validate_required([:action, :target_ref, :board_id, :moderator_did, :reason_code])
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:reason_code, AnsibleRelay.ForumHost.ReportReason.codes())
  end
end
