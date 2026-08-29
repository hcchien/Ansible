defmodule AnsibleRelay.SafetyReports do
  @moduledoc """
  Operator-visible safety reports created by explicit user report/block actions.

  These records are an intake and audit queue only. They do not delete content,
  change trust tier, or globally restrict the reported DID. Host/community
  moderation remains reason-coded and scoped to the host that takes an action.
  """

  import Ecto.Query

  alias AnsibleRelay.Db.SafetyEvent
  alias AnsibleRelay.ForumHost.ReportReason
  alias AnsibleRelay.Repo

  def create(attrs) do
    with :ok <- ReportReason.validate(attrs[:reason_code], attrs[:note]),
         :ok <- validate_distinct_users(attrs[:reporter_did], attrs[:subject_did]),
         :ok <- validate_shape(attrs) do
      changeset = SafetyEvent.changeset(%SafetyEvent{}, Map.put(attrs, :status, "open"))

      case Repo.insert(changeset) do
        {:ok, event} ->
          {:ok, :created, event}

        {:error, changeset} ->
          case open_duplicate(attrs) do
            %SafetyEvent{} = existing -> {:ok, :duplicate, existing}
            nil -> {:error, changeset}
          end
      end
    end
  end

  def list_open do
    SafetyEvent
    |> where(status: "open")
    |> order_by(desc: :id)
    |> Repo.all()
  end

  defp validate_distinct_users(reporter, subject)
       when is_binary(reporter) and is_binary(subject) and reporter == subject,
       do: {:error, :cannot_report_self}

  defp validate_distinct_users(_reporter, _subject), do: :ok

  defp validate_shape(attrs) do
    if attrs[:event_type] in SafetyEvent.event_types() and
         attrs[:target_kind] in SafetyEvent.target_kinds() and
         present?(attrs[:reporter_did]) and present?(attrs[:target_ref]) and
         (attrs[:event_type] != "block_user" or present?(attrs[:subject_did])) do
      :ok
    else
      {:error, :invalid_safety_event}
    end
  end

  defp open_duplicate(attrs) do
    Repo.one(
      from(e in SafetyEvent,
        where:
          e.reporter_did == ^attrs[:reporter_did] and
            e.event_type == ^attrs[:event_type] and
            e.target_kind == ^attrs[:target_kind] and
            e.target_ref == ^attrs[:target_ref] and e.status == "open",
        limit: 1
      )
    )
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
