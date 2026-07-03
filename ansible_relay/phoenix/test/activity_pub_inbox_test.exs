defmodule AnsibleRelay.ActivityPub.InboxTest do
  @moduledoc """
  Inbound AP core behaviors: Follow records the follower + enqueues an
  Accept through the retrying delivery queue; Undo Follow removes it;
  unknown types are acknowledged and ignored.
  """

  use ExUnit.Case, async: false
  use Plug.Test

  import Ecto.Query

  alias AnsibleRelay.ActivityPub.Inbox
  alias AnsibleRelay.Db.{ActivityPubDeliveryAttempt, ActivityPubFollower}
  alias AnsibleRelay.{Repo, Web.Router}

  @router_opts Router.init([])
  @remote "https://mastodon.example/users/mira"
  @remote_inbox "https://mastodon.example/users/mira/inbox"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp fetcher(inbox \\ @remote_inbox) do
    fn actor_url ->
      assert actor_url == @remote
      {:ok, %{"inbox" => inbox}}
    end
  end

  defp follow_activity do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "#{@remote}#follows/1",
      "type" => "Follow",
      "actor" => @remote,
      "object" => "https://relay.elix.cool/users/forum_host"
    }
  end

  test "Follow records the follower and enqueues an Accept" do
    assert {:accepted, :follow} =
             Inbox.handle("forum_host", follow_activity(), actor_fetcher: fetcher())

    assert [follower] = Inbox.followers("forum_host")
    assert follower.remote_actor == @remote
    assert follower.remote_inbox == @remote_inbox

    assert [attempt] = Repo.all(ActivityPubDeliveryAttempt)
    assert attempt.activity_type == "Accept"
    assert attempt.remote_inbox == @remote_inbox
    assert attempt.status == "pending"
    assert attempt.payload["object"]["id"] == follow_activity()["id"]

    # Idempotent: replaying the same Follow neither duplicates the follower
    # nor enqueues a second Accept.
    assert {:accepted, :follow} =
             Inbox.handle("forum_host", follow_activity(), actor_fetcher: fetcher())

    assert length(Inbox.followers("forum_host")) == 1
    assert Repo.aggregate(ActivityPubDeliveryAttempt, :count) == 1
  end

  test "Undo Follow removes the follower" do
    {:accepted, :follow} =
      Inbox.handle("forum_host", follow_activity(), actor_fetcher: fetcher())

    undo = %{
      "type" => "Undo",
      "actor" => @remote,
      "object" => %{"type" => "Follow", "actor" => @remote}
    }

    assert {:accepted, :unfollow} = Inbox.handle("forum_host", undo)
    assert Inbox.followers("forum_host") == []
  end

  test "an unreachable follower actor drops the Follow (no dangling rows)" do
    fetch_fail = fn _url -> {:error, :unreachable} end

    assert {:error, :malformed} =
             Inbox.handle("forum_host", follow_activity(), actor_fetcher: fetch_fail)

    assert Inbox.followers("forum_host") == []
    assert Repo.aggregate(ActivityPubDeliveryAttempt, :count) == 0
  end

  test "unknown activity types are acknowledged and ignored" do
    assert {:accepted, :ignored} =
             Inbox.handle("forum_host", %{"type" => "Like", "actor" => @remote})

    assert Inbox.followers("forum_host") == []
  end

  test "the inbox endpoint reports the handled behavior (still 202)" do
    response =
      conn(:post, "/users/forum_host/inbox", Jason.encode!(%{"type" => "Like"}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["behavior"] == "ignored"
  end

  test "followers are scoped per local actor" do
    {:accepted, :follow} =
      Inbox.handle("forum_host", follow_activity(), actor_fetcher: fetcher())

    assert Inbox.followers("other_actor") == []

    assert Repo.aggregate(
             from(f in ActivityPubFollower, where: f.actor == "forum_host"),
             :count
           ) == 1
  end
end
