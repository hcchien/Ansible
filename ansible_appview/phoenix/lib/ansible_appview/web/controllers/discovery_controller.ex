defmodule AnsibleAppview.Web.Controllers.DiscoveryController do
  @moduledoc "Discovery read API: who-to-follow, explore, and search."

  import Plug.Conn
  alias AnsibleAppview.{Discovery, Metrics, Profiles}

  # GET /api/v1/suggest/follows?reader=did:...&limit=
  def suggest_follows(conn, params) do
    instrument("suggest", fn ->
      reader = params["reader"]

      if is_binary(reader) and reader != "" do
        items = Discovery.suggested_follows(reader, parse_int(params["limit"]) || 20)
        send_json(conn, 200, %{items: items})
      else
        send_json(conn, 422, %{error: "reader_required"})
      end
    end)
  end

  # GET /api/v1/explore?cursor=&limit=
  def explore(conn, params) do
    instrument("explore", fn ->
      result = Discovery.explore(parse_int(params["cursor"]), parse_int(params["limit"]) || 50)
      send_json(conn, 200, result)
    end)
  end

  # GET /api/v1/search/actors?q=&limit=
  def search_actors(conn, params) do
    instrument("search_actors", fn ->
      q = params["q"] || ""
      items = Profiles.search(q, parse_int(params["limit"]) || 20)
      send_json(conn, 200, %{items: items})
    end)
  end

  # GET /api/v1/profiles/:did
  #
  # Resolve only the public profile projection.  A raw DID remains the stable
  # identity; display_name is presentation data and must never be treated as an
  # authorization or verification signal by clients.
  def profile(conn, %{"did" => did}) do
    instrument("profile", fn ->
      case Profiles.get(did) do
        nil -> send_json(conn, 404, %{error: "profile_not_found"})
        profile -> send_json(conn, 200, Profiles.to_map(profile))
      end
    end)
  end

  # GET /api/v1/search?q=&limit=  -> {actors: [...], posts: [...]}
  def search(conn, params) do
    instrument("search", fn ->
      q = params["q"] || ""
      result = Discovery.search(q, parse_int(params["limit"]) || 20)
      send_json(conn, 200, result)
    end)
  end

  defp instrument(kind, fun) do
    Metrics.inc("appview_discovery_requests_total", %{kind: kind})
    Metrics.time("appview_discovery_request_duration_seconds", %{kind: kind}, fun)
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
