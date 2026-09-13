defmodule AnsibleRelay.Web.Controllers.PublicReadsController do
  import Plug.Conn
  alias AnsibleRelay.PublicReads

  def show(conn, action, params) do
    case action do
      :explore ->
        json(conn, 200, PublicReads.explore(params))

      :timeline ->
        dids = params["dids"]

        if is_list(dids) and length(dids) <= 500 and Enum.all?(dids, &is_binary/1),
          do: json(conn, 200, PublicReads.timeline(dids, params)),
          else: json(conn, 422, %{error: "invalid_authors"})

      :thread ->
        json(conn, 200, PublicReads.thread(params["id"], params))

      :search ->
        json(conn, 200, PublicReads.search(params))

      :actors ->
        json(conn, 200, PublicReads.actors(params))

      :suggest ->
        result = PublicReads.actors(params)

        json(conn, 200, %{
          result
          | items: Enum.reject(result.items, &(&1.did == params["reader"]))
        })

      :profile ->
        case PublicReads.profile(params["did"]) do
          nil -> json(conn, 404, %{error: "profile_not_found"})
          actor -> json(conn, 200, actor)
        end

      :content ->
        case PublicReads.content(params["type"], params["id"]) do
          {:ok, item} -> json(conn, 200, %{item: item})
          {:error, :deleted} -> json(conn, 410, %{error: "content_deleted"})
          {:error, _} -> json(conn, 404, %{error: "content_unavailable"})
        end
    end
  end

  defp json(conn, status, value),
    do:
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(value))
end
