defmodule AnsibleRelay.PublicExternalReads do
  @moduledoc """
  Explicit external lane over the Relay's authenticated public ActivityPub
  inbox. Operator-configured sources map actor URIs to boards. No Viewer proxy,
  implicit outbox crawling, native signature badge or trust-tier promotion.
  """
  import Ecto.Query
  alias AnsibleRelay.{Repo, Db.ActivityPubInboundActivity}
  alias AnsibleRelay.ForumHost.PostingGate

  def for_board(board_id, params) do
    board = PostingGate.get_board(board_id)

    sources =
      Application.get_env(:ansible_relay, :external_sources, [])
      |> Enum.filter(fn source ->
        source[:board_id] in [board_id, board && board.hosted_board_id] and
          source[:enabled] != false
      end)

    actors = Enum.map(sources, & &1[:actor_uri]) |> Enum.filter(&is_binary/1)

    if public_external_board?(board) and actors != [] do
      latest =
        from(a in ActivityPubInboundActivity,
          where: a.remote_actor in ^actors,
          distinct: [a.remote_actor, a.object_id],
          order_by: [asc: a.remote_actor, asc: a.object_id, desc: a.id]
        )

      cursor = parse(params["cursor"], 0)
      limit = parse(params["limit"], 50) |> min(200) |> max(1)

      query =
        from(a in subquery(latest),
          where: a.activity_type != "Delete",
          order_by: [desc: a.id],
          limit: ^(limit + 1)
        )

      query = if cursor > 0, do: from(a in query, where: a.id < ^cursor), else: query
      rows = Repo.all(query)
      scanned = Enum.take(rows, limit)

      items =
        Enum.flat_map(scanned, fn row ->
          object = row.payload["object"]

          if is_map(object) and public?(object, row.payload) do
            source = Enum.find(sources, &(&1[:actor_uri] == row.remote_actor))

            [
              %{
                log_id: row.id,
                op_id: row.activity_id,
                board_id: board_id,
                content: object["content"] || "",
                created_at: object["published"],
                external_actor_uri: row.remote_actor,
                external_instance: URI.parse(row.remote_actor).host,
                compliance_level: source[:compliance_level] || "unknown",
                reputation_tier: "external_unverified",
                external: true,
                origin: "activitypub",
                sig_verified: false
              }
            ]
          else
            []
          end
        end)

      %{
        items: items,
        next_cursor: if(scanned == [], do: nil, else: to_string(List.last(scanned).id)),
        has_more: length(rows) > limit
      }
    else
      %{items: [], next_cursor: nil, has_more: false}
    end
  end

  defp public_external_board?(%{
         content_visibility: "public",
         access_policy: %{"read" => %{"requirement" => "public"}},
         posting_policy: %{"external_inclusion" => true}
       }),
       do: true

  defp public_external_board?(_), do: false

  defp public?(object, activity),
    do:
      Enum.any?([object, activity], fn p ->
        "https://www.w3.org/ns/activitystreams#Public" in (List.wrap(p["to"]) ++
                                                             List.wrap(p["cc"]))
      end)

  defp parse(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse(_, default), do: default
end
