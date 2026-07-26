defmodule AnsibleRelay.ActivityPubDeliveryTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.ActivityPub.{ActivityBuilder, DeliveryQueue}
  alias AnsibleRelay.{Db.ActivityPubFollower, PublicationIntentStore, Repo}

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

  test "accepting a note fans out to unique follower inboxes" do
    for remote_actor <- ["https://remote.example/users/bob", "https://remote.example/users/cara"] do
      %ActivityPubFollower{}
      |> ActivityPubFollower.changeset(%{
        actor: "alice",
        remote_actor: remote_actor,
        remote_inbox: "https://remote.example/inbox"
      })
      |> Repo.insert!()
    end

    intent = accepted_intent()
    assert [%{remote_inbox: "https://remote.example/inbox", status: "pending"}] =
             DeliveryQueue.list_for_publication(intent.publication_id)
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

    # A second pass past next_retry_at delivers it (503 backoff now elapsed).
    later = DateTime.add(failed.next_retry_at, 1, :second)

    assert {:ok, %{delivered: 1, retryable: 0, permanent: 0}} =
             DeliveryQueue.deliver_pending(fn _attempt, _activity -> {:ok, 202} end, now: later)

    [delivered] = DeliveryQueue.list_for_publication(intent.publication_id)
    assert delivered.status == "delivered"
    assert delivered.attempt_count == 2
  end

  test "deliver_pending honors next_retry_at backoff (skips rows not yet due)" do
    intent = accepted_intent()
    {:ok, _attempt} = DeliveryQueue.enqueue(intent, "https://remote.example/inbox")

    # First failure schedules next_retry_at in the future.
    now = DateTime.utc_now()

    assert {:ok, %{retryable: 1}} =
             DeliveryQueue.deliver_pending(fn _a, _p -> {:ok, 503} end, now: now)

    [failed] = DeliveryQueue.list_for_publication(intent.publication_id)
    assert failed.next_retry_at != nil
    assert DateTime.compare(failed.next_retry_at, now) == :gt

    # A pass whose clock is before next_retry_at must NOT touch the row.
    assert {:ok, %{delivered: 0, retryable: 0, permanent: 0, dead_letter: 0}} =
             DeliveryQueue.deliver_pending(fn _a, _p -> {:ok, 202} end, now: now)

    [still_pending] = DeliveryQueue.list_for_publication(intent.publication_id)
    assert still_pending.attempt_count == 1

    # Once the clock is past next_retry_at, the row is delivered.
    later = DateTime.add(failed.next_retry_at, 1, :second)

    assert {:ok, %{delivered: 1}} =
             DeliveryQueue.deliver_pending(fn _a, _p -> {:ok, 202} end, now: later)
  end

  test "deliver_pending dead-letters after the max-attempt cap" do
    intent = accepted_intent()
    {:ok, _attempt} = DeliveryQueue.enqueue(intent, "https://remote.example/inbox")

    # Repeatedly fail with a low cap; each pass advances the clock past the
    # scheduled backoff so the row is eligible again.
    now = DateTime.utc_now()

    final =
      Enum.reduce(1..3, now, fn _i, clock ->
        {:ok, _} = DeliveryQueue.deliver_pending(fn _a, _p -> {:ok, 503} end, now: clock, max_attempts: 3)
        [row] = DeliveryQueue.list_for_publication(intent.publication_id)
        if row.next_retry_at, do: DateTime.add(row.next_retry_at, 1, :second), else: clock
      end)

    _ = final
    [dead] = DeliveryQueue.list_for_publication(intent.publication_id)
    assert dead.status == "dead_letter"
    assert dead.attempt_count == 3

    # A dead-lettered row is no longer picked up by future passes.
    assert {:ok, %{delivered: 0, retryable: 0, permanent: 0, dead_letter: 0}} =
             DeliveryQueue.deliver_pending(fn _a, _p -> {:ok, 202} end,
               now: DateTime.add(now, 100_000, :second)
             )
  end
end
