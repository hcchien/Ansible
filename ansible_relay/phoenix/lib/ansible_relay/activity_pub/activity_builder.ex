defmodule AnsibleRelay.ActivityPub.ActivityBuilder do
  @moduledoc "Projects accepted publication intents into ActivityPub activities."

  alias AnsibleRelay.Db.PublicationIntent
  alias AnsibleRelay.ActivityPub.Actor

  @public "https://www.w3.org/ns/activitystreams#Public"

  def actor_name(%PublicationIntent{} = intent) do
    case intent.payload do
      %{"actor" => actor} when is_binary(actor) and actor != "" ->
        slug(actor)

      _ ->
        slug(intent.author_did)
    end
  end

  def from_intent(%PublicationIntent{} = intent, opts) do
    base_url = Keyword.fetch!(opts, :base_url)
    activity_type = activity_type(intent.action)
    actor = Actor.actor_url(actor_name(intent), base_url)
    object = object_for(intent, base_url)

    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "#{base_url}/activities/#{intent.publication_id}",
      "type" => activity_type,
      "actor" => actor,
      "published" => DateTime.to_iso8601(intent.received_at || intent.inserted_at),
      "to" => audience(intent.visibility, actor).to,
      "cc" => audience(intent.visibility, actor).cc,
      "object" => object
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp activity_type("publish"), do: "Create"
  defp activity_type("update"), do: "Update"
  defp activity_type("delete"), do: "Delete"

  defp object_for(%PublicationIntent{action: "delete"} = intent, base_url) do
    %{
      "id" => "#{base_url}/objects/#{intent.publication_id}",
      "type" => "Tombstone",
      "formerType" => object_type(intent),
      "deleted" => DateTime.to_iso8601(intent.received_at || intent.inserted_at)
    }
  end

  defp object_for(%PublicationIntent{} = intent, base_url) do
    actor = Actor.actor_url(actor_name(intent), base_url)
    audience = audience(intent.visibility, actor)

    %{
      "id" => "#{base_url}/objects/#{intent.publication_id}",
      "type" => object_type(intent),
      "attributedTo" => actor,
      "name" => intent.payload["title"],
      "content" => intent.payload["body"] || intent.payload["text"] || "",
      "published" => intent.payload["created_at"],
      "updated" => intent.payload["updated_at"],
      "to" => audience.to,
      "cc" => audience.cc
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp object_type(%PublicationIntent{payload: %{"type" => "article"}}), do: "Article"
  defp object_type(%PublicationIntent{payload: %{"type" => "note"}}), do: "Note"
  defp object_type(%PublicationIntent{payload: %{"mode" => "note"}}), do: "Article"
  defp object_type(_intent), do: "Note"

  defp audience("public", actor),
    do: %{to: [@public], cc: ["#{actor}/followers"]}

  # Unlisted is still public federation, never privacy. Address followers
  # directly and copy Public so compatible servers deliver it without placing
  # it in public discovery surfaces.
  defp audience("unlisted", actor),
    do: %{to: ["#{actor}/followers"], cc: [@public]}

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "actor"
      actor -> actor
    end
  end
end
