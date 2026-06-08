defmodule AnsibleRelay.ActivityPubDeliveryTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.ActivityPub.{ActivityBuilder, DeliveryQueue}
  alias AnsibleRelay.{PublicationIntentStore, Repo}

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

    {:ok, intent} = PublicationIntentStore.accept(Map.merge(defaults, Map.new(attrs)))
    intent
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "builder maps publish, update, and delete intents to ActivityPub activities" do
    create = accepted_intent(action: "publish")
    update = accepted_intent(action: "update")
    delete = accepted_intent(action: "delete")

    assert ActivityBuilder.from_intent(create, base_url: "https://relay.elix.cool")["type"] ==
             "Create"

    assert ActivityBuilder.from_intent(update, base_url: "https://relay.elix.cool")["type"] ==
             "Update"

    delete_activity = ActivityBuilder.from_intent(delete, base_url: "https://relay.elix.cool")
    assert delete_activity["type"] == "Delete"
    assert delete_activity["object"]["type"] == "Tombstone"
  end

  test "delivery queue stores per-inbox status and retries transient failures" do
    intent = accepted_intent()
    {:ok, _attempt} = DeliveryQueue.enqueue(intent, "https://remote.example/inbox")

    assert [%{status: "pending"}] = DeliveryQueue.list_for_publication(intent.publication_id)

    assert {:ok, %{delivered: 0, retryable: 1, permanent: 0}} =
             DeliveryQueue.deliver_pending(fn _attempt, _activity -> {:ok, 503} end)

    [failed] = DeliveryQueue.list_for_publication(intent.publication_id)
    assert failed.status == "retryable"
    assert failed.attempt_count == 1
    assert failed.next_retry_at != nil

    assert {:ok, %{delivered: 1, retryable: 0, permanent: 0}} =
             DeliveryQueue.deliver_pending(fn _attempt, _activity -> {:ok, 202} end)

    [delivered] = DeliveryQueue.list_for_publication(intent.publication_id)
    assert delivered.status == "delivered"
    assert delivered.attempt_count == 2
  end
end
