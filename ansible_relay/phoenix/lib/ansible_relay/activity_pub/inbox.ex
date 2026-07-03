defmodule AnsibleRelay.ActivityPub.Inbox do
  @moduledoc """
  Inbound ActivityPub behaviors (architecture plan Phase 4, partial → core):

    * `Follow`      — record the follower, enqueue an `Accept` back to the
                      follower's inbox (delivered by the existing retrying
                      DeliveryQueue/poller).
    * `Undo Follow` — remove the follower.
    * anything else — acknowledged and ignored (as before).

  The remote actor's inbox comes from fetching its actor document (the
  Follow activity does not carry it); the fetcher is injectable for tests
  and uses OTP `:httpc` in production, same as the federated resolver.

  ## Trust boundary (deliberate scope)

  Inbound activities are NOT HTTP-signature-verified yet — that is the
  remaining "full federation behavior" item. The consequences are bounded
  by design: AP follower edges live only on the AP mirror (this table) and
  are never trust-bearing for native surfaces — external content is never
  `sig_verified`, never surfaces on verified boards, and reputation comes
  only from issuer-signed attestations. A forged Follow adds a cosmetic
  mirror edge; a forged Undo removes one. HTTP signature verification
  upgrades this from cosmetic-integrity to authenticated.
  """

  import Ecto.Query

  alias AnsibleRelay.{Db.ActivityPubFollower, Repo}
  alias AnsibleRelay.Db.ActivityPubDeliveryAttempt

  @doc """
  Handles a parsed inbox activity for [actor]. Returns
  `{:accepted, kind}` where kind names what happened
  (`:follow | :unfollow | :ignored`), or `{:error, :malformed}`.
  """
  def handle(actor, activity, opts \\ [])

  def handle(actor, %{"type" => "Follow"} = activity, opts) do
    remote_actor = activity["actor"]
    follow_id = activity["id"]

    with true <- is_binary(remote_actor) and remote_actor != "",
         {:ok, inbox} <- remote_inbox(remote_actor, opts) do
      upsert_follower(actor, remote_actor, inbox, follow_id)
      enqueue_accept(actor, activity, inbox, opts)
      {:accepted, :follow}
    else
      _ -> {:error, :malformed}
    end
  end

  def handle(actor, %{"type" => "Undo", "object" => %{"type" => "Follow"} = follow}, _opts) do
    remote_actor = follow["actor"]

    if is_binary(remote_actor) and remote_actor != "" do
      Repo.delete_all(
        from(f in ActivityPubFollower,
          where: f.actor == ^actor and f.remote_actor == ^remote_actor
        )
      )

      {:accepted, :unfollow}
    else
      {:error, :malformed}
    end
  end

  def handle(_actor, activity, _opts) when is_map(activity), do: {:accepted, :ignored}
  def handle(_actor, _activity, _opts), do: {:error, :malformed}

  @doc "Followers of a local actor (AP mirror edges)."
  def followers(actor) do
    Repo.all(
      from(f in ActivityPubFollower,
        where: f.actor == ^actor,
        order_by: [asc: f.remote_actor]
      )
    )
  end

  # --- internals ---

  defp upsert_follower(actor, remote_actor, inbox, follow_id) do
    %ActivityPubFollower{}
    |> ActivityPubFollower.changeset(%{
      actor: actor,
      remote_actor: remote_actor,
      remote_inbox: inbox,
      follow_activity_id: follow_id
    })
    |> Repo.insert(
      on_conflict: {:replace, [:remote_inbox, :follow_activity_id, :updated_at]},
      conflict_target: [:actor, :remote_actor]
    )
  end

  # The Accept rides the existing delivery queue (retry/backoff/dead-letter).
  # The queue rows are keyed by (publication_id, remote_inbox); a synthetic
  # publication id namespaced by the follow keeps Accepts idempotent.
  defp enqueue_accept(actor, follow_activity, inbox, opts) do
    base_url = Keyword.get(opts, :base_url, "https://relay.elix.cool")
    actor_uri = "#{base_url}/users/#{actor}"

    accept = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "#{actor_uri}#accepts/#{:erlang.phash2(follow_activity["id"] || follow_activity)}",
      "type" => "Accept",
      "actor" => actor_uri,
      "object" => follow_activity
    }

    %ActivityPubDeliveryAttempt{}
    |> ActivityPubDeliveryAttempt.changeset(%{
      publication_id: "ap-accept:#{accept["id"]}",
      remote_inbox: inbox,
      activity_id: accept["id"],
      activity_type: "Accept",
      payload: accept,
      status: "pending",
      attempt_count: 0
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  # Resolve the remote actor document → its inbox URL. Injectable
  # (`:actor_fetcher`) for tests; :httpc in production. Only https actors
  # are accepted.
  defp remote_inbox(remote_actor, opts) do
    fetcher = Keyword.get(opts, :actor_fetcher, &fetch_actor_document/1)

    with true <- String.starts_with?(remote_actor, "https://"),
         {:ok, %{} = document} <- fetcher.(remote_actor),
         inbox when is_binary(inbox) and inbox != "" <-
           document["inbox"] || get_in(document, ["endpoints", "sharedInbox"]) do
      {:ok, inbox}
    else
      _ -> {:error, :no_inbox}
    end
  end

  defp fetch_actor_document(url) do
    case :httpc.request(
           :get,
           {String.to_charlist(url), [{~c"accept", ~c"application/activity+json"}]},
           [timeout: 5_000, connect_timeout: 3_000],
           body_format: :binary
         ) do
      {:ok, {{_http, 200, _status}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, document} when is_map(document) -> {:ok, document}
          _ -> {:error, :bad_document}
        end

      _ ->
        {:error, :unreachable}
    end
  end
end
