defmodule AnsibleRelay.Web.ActivityPubControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Db.{ActivityPubInboundActivity, FediversePreference}
  alias AnsibleRelay.{DidAccountCache, PublicationIntentStore, Repo}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp get_json(path) do
    %{conn(:get, path) | host: "relay.elix.cool", scheme: :https, port: 443}
    |> Router.call(@router_opts)
  end

  defp post_json(path, body) do
    %{
      conn(:post, path, Jason.encode!(body))
      | host: "relay.elix.cool",
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

    DidAccountCache.put(
      "did:key:z6MkAlice",
      String.duplicate("a", 64),
      "alice",
      reputation_tier: "verified_human"
    )

    Repo.insert!(%FediversePreference{
      did: "did:key:z6MkAlice",
      actor: "alice",
      enabled: true,
      revision: 1,
      signature: String.duplicate("a", 128),
      signature_scheme: "ed25519"
    })

    previous = Application.get_env(:ansible_relay, :activity_pub_inbound_verifier)
    previous_public_key = Application.get_env(:ansible_relay, :activity_pub_public_key_pem)
    Application.put_env(:ansible_relay, :activity_pub_inbound_verifier, fn _, _ -> {:ok, %{}} end)
    Application.put_env(:ansible_relay, :activity_pub_public_key_pem, "TEST PUBLIC KEY")

    on_exit(fn ->
      Application.put_env(:ansible_relay, :activity_pub_inbound_verifier, previous)
      Application.put_env(:ansible_relay, :activity_pub_public_key_pem, previous_public_key)
    end)

    :ok
  end

  test "webfinger returns relay-domain actor link" do
    accepted_intent()
    response = get_json("/.well-known/webfinger?resource=acct:alice@relay.elix.cool")

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["subject"] == "acct:alice@relay.elix.cool"

    assert [%{"rel" => "self", "type" => "application/activity+json", "href" => href}] =
             body["links"]

    assert href == "https://relay.elix.cool/users/alice"
  end

  test "actor endpoint returns ActivityPub actor document" do
    accepted_intent()
    response = get_json("/users/alice")

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["@context"] == "https://www.w3.org/ns/activitystreams"
    assert body["id"] == "https://relay.elix.cool/users/alice"
    assert body["type"] == "Person"
    assert body["preferredUsername"] == "alice"
    assert body["inbox"] == "https://relay.elix.cool/users/alice/inbox"
    assert body["outbox"] == "https://relay.elix.cool/users/alice/outbox"
  end

  test "deleted actor remains key-resolvable but is no longer discoverable" do
    preference = Repo.get_by!(FediversePreference, actor: "alice")
    Repo.update!(Ecto.Changeset.change(preference, enabled: false))

    actor_response = get_json("/users/alice")
    assert actor_response.status == 200
    assert Jason.decode!(actor_response.resp_body)["suspended"] == true
    assert Jason.decode!(actor_response.resp_body)["publicKey"]["id"] =~ "#main-key"

    webfinger = get_json("/.well-known/webfinger?resource=acct:alice@relay.elix.cool")
    assert webfinger.status == 404
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
    assert activity["id"] == "https://relay.elix.cool/activities/#{intent.publication_id}"
    assert activity["actor"] == "https://relay.elix.cool/users/alice"
    assert activity["object"]["type"] == "Note"
    assert activity["object"]["name"] == "ActivityPub note"
  end

  test "inbox durably records an authenticated public remote Create" do
    accepted_intent()
    remote_actor = "https://remote.example/users/bob"
    object_id = "https://remote.example/notes/1"
    public = "https://www.w3.org/ns/activitystreams#Public"

    response =
      post_json("/users/alice/inbox", %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/1",
        "type" => "Create",
        "actor" => remote_actor,
        "to" => [public],
        "object" => %{
          "id" => object_id,
          "type" => "Note",
          "attributedTo" => remote_actor,
          "to" => [public],
          "content" => "hello"
        }
      })

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["behavior"] == "external_content"

    assert [%{object_id: ^object_id, remote_actor: ^remote_actor}] =
             Repo.all(ActivityPubInboundActivity)

    delta = get_json("/api/v1/federation/inbound?cursor=0&limit=10")
    assert delta.status == 200
    assert [%{"object_id" => ^object_id}] = Jason.decode!(delta.resp_body)["activities"]
  end
end
