defmodule AnsibleRelay.Web.Controllers.ActivityPubController do
  @moduledoc "Relay-owned ActivityPub discovery, actor, inbox, and outbox endpoints."

  import Plug.Conn

  alias AnsibleRelay.ActivityPub.{Actor, ActivityBuilder}
  alias AnsibleRelay.PublicationIntentStore

  def webfinger(conn, %{"resource" => "acct:" <> account}) do
    with [actor, host] <- String.split(account, "@", parts: 2),
         true <- host == conn.host do
      send_json(
        conn,
        200,
        Actor.webfinger(actor, base_url(conn), conn.host),
        "application/jrd+json"
      )
    else
      _ -> send_json(conn, 404, %{error: "actor_not_found"})
    end
  end

  def webfinger(conn, _params), do: send_json(conn, 422, %{error: "missing_resource"})

  def actor(conn, %{"actor" => actor}) do
    send_json(conn, 200, Actor.document(actor, base_url(conn)), "application/activity+json")
  end

  # Inbound AP behaviors (Phase 4 core): Follow → record + Accept back;
  # Undo Follow → remove. Always 202 toward the remote server (AP inboxes
  # are best-effort; a malformed activity is dropped, never errored back),
  # with the handled behavior echoed for observability/tests.
  def inbox(conn, %{"actor" => actor}) do
    case AnsibleRelay.ActivityPub.Inbox.handle(actor, conn.body_params,
           base_url: base_url(conn)
         ) do
      {:accepted, kind} ->
        send_json(conn, 202, %{accepted: true, actor: actor, behavior: to_string(kind)})

      {:error, :malformed} ->
        send_json(conn, 202, %{accepted: true, actor: actor, behavior: "dropped"})
    end
  end

  def outbox(conn, %{"actor" => actor}) do
    base_url = base_url(conn)

    activities =
      actor
      |> PublicationIntentStore.list_for_actor()
      |> Enum.map(&ActivityBuilder.from_intent(&1, base_url: base_url))

    send_json(
      conn,
      200,
      %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "#{base_url}/users/#{actor}/outbox",
        "type" => "OrderedCollection",
        "totalItems" => length(activities),
        "orderedItems" => activities
      },
      "application/activity+json"
    )
  end

  defp base_url(conn) do
    default_port? =
      (conn.scheme == :https && conn.port == 443) || (conn.scheme == :http && conn.port == 80)

    port = if default_port?, do: "", else: ":#{conn.port}"
    "#{conn.scheme}://#{conn.host}#{port}"
  end

  defp send_json(conn, status, body, content_type \\ "application/json") do
    conn
    |> put_resp_content_type(content_type)
    |> send_resp(status, Jason.encode!(body))
  end
end
