defmodule AnsibleRelay.ActivityPub.DeliveryQueue do
  @moduledoc "Stores ActivityPub delivery attempts and retry state."

  import Ecto.Query

  alias AnsibleRelay.{Repo, Db.ActivityPubDeliveryAttempt}
  alias AnsibleRelay.ActivityPub.ActivityBuilder

  def enqueue(intent, remote_inbox, opts \\ []) when is_binary(remote_inbox) do
    base_url = Keyword.get(opts, :base_url, "https://relay.elix.cool")
    activity = ActivityBuilder.from_intent(intent, base_url: base_url)

    attrs = %{
      publication_id: intent.publication_id,
      remote_inbox: remote_inbox,
      activity_id: activity["id"],
      activity_type: activity["type"],
      payload: activity,
      status: "pending",
      attempt_count: 0
    }

    %ActivityPubDeliveryAttempt{}
    |> ActivityPubDeliveryAttempt.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, attempt} -> {:ok, attempt}
      {:error, %Ecto.Changeset{} = changeset} -> duplicate_or_error(changeset)
    end
  end

  def list_for_publication(publication_id) do
    ActivityPubDeliveryAttempt
    |> where([attempt], attempt.publication_id == ^publication_id)
    |> order_by([attempt], asc: attempt.remote_inbox)
    |> Repo.all()
  end

  def deliver_pending(client, opts \\ []) when is_function(client, 2) do
    limit = Keyword.get(opts, :limit, 50)

    attempts =
      ActivityPubDeliveryAttempt
      |> where([attempt], attempt.status in ["pending", "retryable"])
      |> order_by([attempt], asc: attempt.inserted_at)
      |> limit(^limit)
      |> Repo.all()

    result = %{delivered: 0, retryable: 0, permanent: 0}

    result =
      Enum.reduce(attempts, result, fn attempt, acc ->
        case deliver_attempt(attempt, client) do
          {:ok, "delivered"} -> Map.update!(acc, :delivered, &(&1 + 1))
          {:ok, "retryable"} -> Map.update!(acc, :retryable, &(&1 + 1))
          {:ok, "permanent_failure"} -> Map.update!(acc, :permanent, &(&1 + 1))
        end
      end)

    {:ok, result}
  end

  defp deliver_attempt(attempt, client) do
    case client.(attempt, attempt.payload) do
      {:ok, status} when status in 200..299 ->
        update_attempt(attempt, "delivered", nil)

      {:ok, status} when status >= 500 ->
        update_attempt(attempt, "retryable", "remote_http_#{status}")

      {:ok, status} ->
        update_attempt(attempt, "permanent_failure", "remote_http_#{status}")

      {:error, reason} ->
        update_attempt(attempt, "retryable", inspect(reason))
    end
  end

  defp update_attempt(attempt, status, error) do
    now = DateTime.utc_now()

    next_retry_at =
      if status == "retryable" do
        DateTime.add(now, retry_delay_seconds(attempt.attempt_count + 1), :second)
      end

    attempt
    |> ActivityPubDeliveryAttempt.changeset(%{
      status: status,
      attempt_count: attempt.attempt_count + 1,
      last_attempt_at: now,
      next_retry_at: next_retry_at,
      last_error: error
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated.status}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp retry_delay_seconds(attempt_count), do: min(3600, trunc(:math.pow(2, attempt_count)))

  defp duplicate_or_error(changeset) do
    if Enum.any?(changeset.errors, &unique_error?/1) do
      {:error, :duplicate}
    else
      {:error, changeset}
    end
  end

  defp unique_error?({_field, {_message, opts}}), do: opts[:constraint] == :unique
  defp unique_error?(_error), do: false
end
