defmodule AnsibleRelay.PublicationIntentStore do
  @moduledoc """
  Durable store for app-signed publication intents accepted by the relay.

  Accepted rows are the input queue for later ActivityPub projection and
  delivery. This module deliberately does not perform federation itself.
  """

  import Ecto.Query

  alias AnsibleRelay.{FediversePreferences, Repo, Db.PublicationIntent}
  alias AnsibleRelay.ActivityPub.{ActivityBuilder, DeliveryQueue, Inbox}

  def accept(attrs) do
    attrs =
      attrs
      |> Map.put(:publication_id, publication_id(attrs.intent_id))
      |> Map.put(:status, "accepted")
      |> Map.put(:delivery_status, "queued")
      |> Map.put(:received_at, DateTime.utc_now())

    %PublicationIntent{}
    |> PublicationIntent.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, intent} ->
        fan_out_to_followers(intent)

      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate?(changeset) do
          {:error, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  def publication_id(intent_id) when is_binary(intent_id) do
    digest =
      :crypto.hash(:sha256, intent_id)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 32)

    "pub_#{digest}"
  end

  def list_accepted do
    PublicationIntent
    |> where([intent], intent.status == "accepted")
    |> order_by([intent], asc: intent.inserted_at)
    |> Repo.all()
  end

  def list_for_actor(actor) when is_binary(actor) do
    list_accepted()
    |> Enum.filter(&(ActivityBuilder.actor_name(&1) == actor))
  end

  def get_by_publication_id(publication_id) when is_binary(publication_id),
    do: Repo.get_by(PublicationIntent, publication_id: publication_id)

  def actor_enabled?(actor) when is_binary(actor),
    do: FediversePreferences.enabled_actor?(actor)

  # Materialize one durable delivery attempt per follower inbox as part of
  # accepting a Note. Delivery itself remains asynchronous and retryable.
  # Duplicate/shared inboxes are collapsed so one remote instance does not
  # receive the same activity repeatedly for multiple followers.
  defp fan_out_to_followers(intent) do
    actor = ActivityBuilder.actor_name(intent)

    preference = FediversePreferences.get_by_actor(actor)

    results =
      actor
      |> Inbox.followers()
      |> Enum.filter(fn follower ->
        FediversePreferences.allowed_remote?(
          preference,
          follower.remote_actor,
          follower.remote_inbox
        )
      end)
      |> Enum.map(& &1.remote_inbox)
      |> Enum.uniq()
      |> Enum.map(fn inbox ->
        case DeliveryQueue.enqueue(intent, inbox) do
          {:ok, _attempt} -> :ok
          {:error, :duplicate} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end)

    if Enum.any?(results, &match?({:error, _}, &1)) do
      case intent
           |> PublicationIntent.changeset(%{delivery_status: "enqueue_failed"})
           |> Repo.update() do
        {:ok, updated} -> {:ok, updated}
        {:error, changeset} -> {:error, changeset}
      end
    else
      delivery_status = if results == [], do: "awaiting_followers", else: "queued"

      case intent
           |> PublicationIntent.changeset(%{delivery_status: delivery_status})
           |> Repo.update() do
        {:ok, updated} -> {:ok, updated}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp duplicate?(changeset) do
    Enum.any?(changeset.errors, fn
      {_field, {_message, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end
end
