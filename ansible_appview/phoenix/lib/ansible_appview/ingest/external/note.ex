defmodule AnsibleAppview.Ingest.External.Note do
  @moduledoc """
  Normalizes a public ActivityPub item (a `Note`, or a `Create` wrapping a Note)
  into the internal external-item shape the ingest path writes.

  Mirrors the relay's outbound AP Note conventions
  (`AnsibleRelay.ActivityPub.ActivityBuilder`): items carry an `id`,
  `attributedTo`/`actor`, `content`, `published`, and `to` recipients. We only
  accept **public** notes (addressed to the AS Public collection), matching the
  "public content only" rule of the constitution review.

  Returns `{:ok, item}` where `item` carries the dedup key (`object_id`), the
  origin (`actor_uri`, `instance`), the content/timestamp, and the recorded
  HTTP-signature status. Returns `:skip` for anything that is not a public Note
  we can attribute (deletes, private items, malformed entries).
  """

  alias AnsibleAppview.Ingest.External.HttpSignature

  @public "https://www.w3.org/ns/activitystreams#Public"

  @doc """
  Normalize one raw outbox entry against its source actor URI.

  `source_actor_uri` is the actor we curated/polled; it is the authoritative
  origin we record (we do not trust a self-declared `attributedTo` that differs).
  """
  @spec normalize(map(), String.t()) :: {:ok, map()} | :skip
  def normalize(raw, source_actor_uri) when is_map(raw) and is_binary(source_actor_uri) do
    object = unwrap(raw)

    with %{} <- object,
         "Note" <- type(object),
         true <- public?(object) || public?(raw),
         object_id when is_binary(object_id) and object_id != "" <- object_id(object) do
      {:ok,
       %{
         object_id: object_id,
         actor_uri: source_actor_uri,
         instance: instance(source_actor_uri),
         content: object["content"] || "",
         name: object["name"],
         published_at: object["published"] || raw["published"],
         http_signature_status: HttpSignature.status(raw)
       }}
    else
      _ -> :skip
    end
  end

  def normalize(_raw, _source), do: :skip

  # A Create activity wraps its Note under "object"; a bare Note is itself.
  defp unwrap(%{"type" => "Create", "object" => %{} = object}), do: object
  defp unwrap(%{"object" => %{} = object} = raw) when is_map_key(raw, "type"), do: object
  defp unwrap(%{} = raw), do: raw

  defp type(%{"type" => t}) when is_binary(t), do: t
  defp type(_), do: nil

  defp object_id(%{"id" => id}), do: id
  defp object_id(_), do: nil

  defp public?(%{} = item) do
    recipients = List.wrap(item["to"]) ++ List.wrap(item["cc"])
    @public in recipients
  end

  # Derive the instance host from the actor URI (e.g. https://m.example/users/a
  # -> "m.example"). Best-effort; falls back to the raw URI.
  defp instance(actor_uri) do
    case URI.parse(actor_uri) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> actor_uri
    end
  end
end
