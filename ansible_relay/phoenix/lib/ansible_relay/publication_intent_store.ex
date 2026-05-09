defmodule AnsibleRelay.PublicationIntentStore do
  @moduledoc """
  Durable store for app-signed publication intents accepted by the relay.

  Accepted rows are the input queue for later ActivityPub projection and
  delivery. This module deliberately does not perform federation itself.
  """

  import Ecto.Query

  alias AnsibleRelay.{Repo, Db.PublicationIntent}
  alias AnsibleRelay.ActivityPub.ActivityBuilder

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
        {:ok, intent}

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

  defp duplicate?(changeset) do
    Enum.any?(changeset.errors, fn
      {_field, {_message, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end
end
