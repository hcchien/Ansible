defmodule AnsibleRelay.ActivityPub.InboundStore do
  @moduledoc """
  Durable append-only log of authenticated public ActivityPub content.

  This log is consumed by AppView's curated external lane. It is not an Elix
  operation log and confers no native signature or reputation.
  """

  import Ecto.Query

  alias AnsibleRelay.{Db.ActivityPubInboundActivity, Repo}

  @public "https://www.w3.org/ns/activitystreams#Public"
  @accepted_types ~w(Create Update Delete)

  def record(local_actor, %{"type" => type} = activity)
      when type in @accepted_types and is_binary(local_actor) do
    with {:ok, attrs} <- normalize(local_actor, activity) do
      %ActivityPubInboundActivity{}
      |> ActivityPubInboundActivity.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :activity_id)
      |> case do
        {:ok, row} -> {:ok, row}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def record(_, _), do: {:error, :unsupported_activity}

  def delta(cursor, limit) do
    rows =
      Repo.all(
        from(a in ActivityPubInboundActivity,
          where: a.id > ^cursor,
          order_by: [asc: a.id],
          limit: ^limit
        )
      )

    next_cursor =
      case List.last(rows) do
        nil -> cursor
        row -> row.id
      end

    %{
      activities: Enum.map(rows, &serialize/1),
      next_cursor: next_cursor,
      has_more: length(rows) == limit
    }
  end

  defp normalize(local_actor, activity) do
    type = activity["type"]
    remote_actor = activity["actor"]
    activity_id = activity["id"]
    object = activity["object"]
    object_id = object_id(object)

    with true <- https_uri?(activity_id),
         true <- https_uri?(remote_actor),
         true <- type == "Delete" or public_note?(activity, object),
         true <- type == "Delete" or attributed_to(object) == remote_actor,
         true <- is_binary(object_id) and object_id != "" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok,
       %{
         activity_id: activity_id,
         local_actor: local_actor,
         remote_actor: remote_actor,
         activity_type: type,
         object_id: object_id,
         payload: activity,
         received_at: now
       }}
    else
      _ -> {:error, :invalid_public_activity}
    end
  end

  defp public_note?(activity, %{"type" => "Note"} = object) do
    recipients =
      List.wrap(activity["to"]) ++
        List.wrap(activity["cc"]) ++
        List.wrap(object["to"]) ++ List.wrap(object["cc"])

    @public in recipients
  end

  defp public_note?(_, _), do: false

  defp attributed_to(%{"attributedTo" => actor}), do: actor
  defp attributed_to(_), do: nil
  defp object_id(%{"id" => id}), do: id
  defp object_id(id) when is_binary(id), do: id
  defp object_id(_), do: nil

  defp https_uri?(value) when is_binary(value) do
    match?(%URI{scheme: "https", host: host} when is_binary(host), URI.parse(value))
  end

  defp https_uri?(_), do: false

  defp serialize(row) do
    %{
      id: row.id,
      activity_id: row.activity_id,
      local_actor: row.local_actor,
      remote_actor: row.remote_actor,
      activity_type: row.activity_type,
      object_id: row.object_id,
      payload: row.payload,
      received_at: DateTime.to_iso8601(row.received_at)
    }
  end
end
