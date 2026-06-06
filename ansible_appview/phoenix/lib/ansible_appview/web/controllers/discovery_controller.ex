defmodule AnsibleAppview.Web.Controllers.DiscoveryController do
  @moduledoc "Discovery read API: who-to-follow, explore, and search."

  import Plug.Conn
  alias AnsibleAppview.Discovery

  # GET /api/v1/suggest/follows?reader=did:...&limit=
  def suggest_follows(conn, params) do
    reader = params["reader"]

    if is_binary(reader) and reader != "" do
      items = Discovery.suggested_follows(reader, parse_int(params["limit"]) || 20)
      send_json(conn, 200, %{items: items})
    else
      send_json(conn, 422, %{error: "reader_required"})
    end
  end

  # GET /api/v1/explore?cursor=&limit=
  def explore(conn, params) do
    result = Discovery.explore(parse_int(params["cursor"]), parse_int(params["limit"]) || 50)
    send_json(conn, 200, result)
  end

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
