defmodule AnsibleRelay.Web.ActivityPubControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{PublicationIntentStore, Repo}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp get_json(path) do
    %{conn(:get, path) | host: "relay.trisaura.io", scheme: :https, port: 443}
    |> Router.call(@router_opts)
  end

  defp post_json(path, body) do
    %{
      conn(:post, path, Jason.encode!(body))
      | host: "relay.trisaura.io",
        scheme: :https,
        port: 443
    }
    |> put_req_header("content-type", "application/activity+json")
    |> Router.call(@router_opts)
  end

  defp accepted_intent(attrs \\ %{}) do
    defaults = %{
      intent_id: "intent-#{System.unique_integer([:positive])}",
      author_did: "did:key:z6MkAlice",
      content_item_id: "note-#{System.unique_integer([:positive])}",
      action: "publish",
      visibility: "public",
      payload: %{
        "actor" => "alice",
        "type" => "note",
        "title" => "ActivityPub note",
        "body" => "Hello federation"
      },
      payload_hash: String.duplicate("a", 64),
      signature: String.duplicate("b", 128),
      signature_scheme: "ed25519"
    }

    {:ok, intent} = PublicationIntentStore.accept(Map.merge(defaults, attrs))
    intent
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "webfinger returns relay-domain actor link" do
    response = get_json("/.well-known/webfinger?resource=acct:alice@relay.trisaura.io")

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["subject"] == "acct:alice@relay.trisaura.io"

    assert [%{"rel" => "self", "type" => "application/activity+json", "href" => href}] =
             body["links"]

    assert href == "https://relay.trisaura.io/users/alice"
  end

  test "actor endpoint returns ActivityPub actor document" do
    response = get_json("/users/alice")

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["@context"] == "https://www.w3.org/ns/activitystreams"
    assert body["id"] == "https://relay.trisaura.io/users/alice"
    assert body["type"] == "Person"
    assert body["preferredUsername"] == "alice"
    assert body["inbox"] == "https://relay.trisaura.io/users/alice/inbox"
    assert body["outbox"] == "https://relay.trisaura.io/users/alice/outbox"
  end

  test "outbox projects accepted publication intents to ActivityPub Create" do
    intent = accepted_intent()

    response = get_json("/users/alice/outbox")

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["type"] == "OrderedCollection"
    assert body["totalItems"] == 1
    [activity] = body["orderedItems"]
    assert activity["type"] == "Create"
    assert activity["id"] == "https://relay.trisaura.io/activities/#{intent.publication_id}"
    assert activity["actor"] == "https://relay.trisaura.io/users/alice"
    assert activity["object"]["type"] == "Note"
    assert activity["object"]["name"] == "ActivityPub note"
  end

  test "inbox endpoint accepts remote ActivityPub activity envelope" do
    response =
      post_json("/users/alice/inbox", %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/1",
        "type" => "Create",
        "actor" => "https://remote.example/users/bob",
        "object" => %{"type" => "Note", "content" => "hello"}
      })

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
  end
end
