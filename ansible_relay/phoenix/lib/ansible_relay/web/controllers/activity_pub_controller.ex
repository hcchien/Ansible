defmodule AnsibleRelay.Web.Controllers.ActivityPubController do
  @moduledoc "Relay-owned ActivityPub discovery, actor, inbox, and outbox endpoints."

  import Plug.Conn

  alias AnsibleRelay.ActivityPub.{Actor, ActivityBuilder, Inbox}
  alias AnsibleRelay.{
    DidAccountCache,
    FediversePreferences,
    PublicationIntentStore,
    ReputationTier
  }

  def webfinger(conn, %{"resource" => "acct:" <> account}) do
    with [actor, host] <- String.split(account, "@", parts: 2),
         true <- host == conn.host,
         {:ok, _did} <- enabled_actor(actor) do
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
    case enabled_actor(actor) do
      {:ok, _did} ->
        send_json(conn, 200, Actor.document(actor, base_url(conn)), "application/activity+json")

      _ ->
        send_json(conn, 404, %{error: "actor_not_found"})
    end
  end

  # Inbound AP behaviors (Phase 4 core): Follow → record + Accept back;
  # Undo Follow → remove. Always 202 toward the remote server (AP inboxes
  # are best-effort; a malformed activity is dropped, never errored back),
  # with the handled behavior echoed for observability/tests.
  def inbox(conn, %{"actor" => actor}) do
    with {:ok, _did} <- enabled_actor(actor),
         %{allow_remote_followers: true} = preference <-
           FediversePreferences.get_by_actor(actor),
         remote_actor when is_binary(remote_actor) <- conn.body_params["actor"],
         true <- FediversePreferences.allowed_remote?(preference, remote_actor) do
      case AnsibleRelay.ActivityPub.Inbox.handle(actor, conn.body_params,
             base_url: base_url(conn),
             remote_policy: fn remote_actor, inbox ->
               FediversePreferences.allowed_remote?(preference, remote_actor, inbox)
             end
           ) do
        {:accepted, kind} ->
          send_json(conn, 202, %{accepted: true, actor: actor, behavior: to_string(kind)})

        {:error, :malformed} ->
          send_json(conn, 202, %{accepted: true, actor: actor, behavior: "dropped"})

        {:error, :blocked} ->
          send_json(conn, 202, %{accepted: true, actor: actor, behavior: "blocked"})
      end
    else
      %{allow_remote_followers: false} ->
        send_json(conn, 202, %{
          accepted: true,
          actor: actor,
          behavior: "remote_follows_disabled"
        })

      false ->
        send_json(conn, 202, %{accepted: true, actor: actor, behavior: "blocked"})

      _ ->
        send_json(conn, 404, %{error: "actor_not_found"})
    end
  end

  def outbox(conn, %{"actor" => actor}) do
    with {:ok, _did} <- enabled_actor(actor) do
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
    else
      _ -> send_json(conn, 404, %{error: "actor_not_found"})
    end
  end

  def followers(conn, %{"actor" => actor}) do
    with {:ok, _did} <- enabled_actor(actor) do
      items = Inbox.followers(actor) |> Enum.map(& &1.remote_actor)

      send_json(
        conn,
        200,
        %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => "#{base_url(conn)}/users/#{actor}/followers",
          "type" => "OrderedCollection",
          "totalItems" => length(items),
          "orderedItems" => items
        },
        "application/activity+json"
      )
    else
      _ -> send_json(conn, 404, %{error: "actor_not_found"})
    end
  end

  def object(conn, %{"publication_id" => publication_id}) do
    case PublicationIntentStore.get_by_publication_id(publication_id) do
      nil ->
        send_json(conn, 404, %{error: "object_not_found"})

      intent ->
        activity = ActivityBuilder.from_intent(intent, base_url: base_url(conn))
        send_json(conn, 200, activity["object"], "application/activity+json")
    end
  end

  defp enabled_actor(handle) do
    with {:ok, did} <- DidAccountCache.get_by_handle(handle),
         true <- ReputationTier.meets?(DidAccountCache.reputation_tier(did), "verified_human"),
         true <- FediversePreferences.enabled_actor?(handle) do
      {:ok, did}
    else
      _ -> :not_found
    end
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
