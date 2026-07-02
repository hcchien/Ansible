defmodule AnsibleRelay.Push.WakeSchedulerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{AbuseDetector, IdentityCache, MessengerStore, OpStore, Repo}
  alias AnsibleRelay.Push.{TestSender, TokenRegistry, WakeScheduler}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    for mod <- [
          IdentityCache,
          AbuseDetector,
          OpStore,
          AnsibleRelay.DidAccountCache,
          MessengerStore,
          WakeScheduler
        ] do
      case mod.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end

    AbuseDetector.reset()
    TestSender.reset()
    :ok = WakeScheduler.reset()
    :ok = TokenRegistry.reset()
    :ok
  end

  # --- Ingest helpers (mirror ops_controller_test) ---

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp signing_payload(op) do
    %{
      "author_did" => op["author_did"],
      "entity_id" => op["entity_id"],
      "entity_type" => op["entity_type"],
      "op_id" => op["op_id"],
      "op_type" => op["op_type"],
      "payload" => op["payload"]
    }
    |> canonical_json()
  end

  defp seed_did(did) do
    {public_key, private_key} = ed25519_keypair()
    :ok = IdentityCache.put(did, public_key, "wake:#{did}")
    private_key
  end

  defp ingest_op(did, private_key, entity_type, entity_id, payload_map) do
    op = %{
      "op_id" => "op-#{System.unique_integer([:positive])}",
      "author_did" => did,
      "entity_type" => entity_type,
      "entity_id" => entity_id,
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(payload_map))
    }

    response =
      post_json("/api/v1/ops", Map.put(op, "signature", sign(private_key, signing_payload(op))))

    assert response.status == 202
    response
  end

  defp register_device(did, categories, overrides \\ %{}) do
    {:ok, _outcome} =
      TokenRegistry.register(
        Map.merge(
          %{
            subject_did: did,
            device_id: "dev_1",
            push_token: "tok_#{did}",
            platform: "fcm",
            categories: categories
          },
          overrides
        )
      )
  end

  defp deliver_message(sender_did, recipient_did) do
    {:ok, _message} =
      MessengerStore.store_message(%{
        "message_id" => "msg-#{System.unique_integer([:positive])}",
        "sender_did" => sender_did,
        "sender_device_id" => "msgdev_sender",
        "recipient_did" => recipient_did,
        "recipient_device_id" => "msgdev_recipient",
        "ciphertext_type" => "pre_key_signal_message",
        "ciphertext" => "base64-ciphertext",
        "protocol_version" => "signal-mvp-v1",
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })
  end

  # Drain the scheduler's cast queue, wait out the debounce window, then
  # drain the flush message so any pending send has happened.
  defp await_flush do
    :sys.get_state(WakeScheduler)
    Process.sleep(Application.fetch_env!(:ansible_relay, :push_wake_debounce_ms) + 50)
    :sys.get_state(WakeScheduler)
    # Sends now run in supervised tasks; wait for them before asserting.
    WakeScheduler.drain()
  end

  test "a reply op wakes the parent thread author's registered device" do
    author = "did:plc:wake_author_#{System.unique_integer([:positive])}"
    replier = "did:plc:wake_replier_#{System.unique_integer([:positive])}"
    author_key = seed_did(author)
    replier_key = seed_did(replier)
    thread_id = "thread-#{System.unique_integer([:positive])}"

    register_device(author, ["reply"])

    ingest_op(author, author_key, "thread", thread_id, %{"title" => "hello"})

    ingest_op(replier, replier_key, "post", "post-#{System.unique_integer([:positive])}", %{
      "threadId" => thread_id,
      "body" => "a reply"
    })

    await_flush()

    assert [%{token: token, platform: "fcm"}] = TestSender.calls()
    assert token == "tok_#{author}"
  end

  test "a self-reply does not wake the thread author" do
    author = "did:plc:wake_selfreply_#{System.unique_integer([:positive])}"
    author_key = seed_did(author)
    thread_id = "thread-#{System.unique_integer([:positive])}"

    register_device(author, ["reply"])

    ingest_op(author, author_key, "thread", thread_id, %{"title" => "hello"})

    ingest_op(author, author_key, "post", "post-#{System.unique_integer([:positive])}", %{
      "threadId" => thread_id,
      "body" => "replying to myself"
    })

    await_flush()
    assert TestSender.calls() == []
  end

  test "a follow op wakes the target DID (carried as entity_id)" do
    target = "did:plc:wake_followed_#{System.unique_integer([:positive])}"
    follower = "did:plc:wake_follower_#{System.unique_integer([:positive])}"
    follower_key = seed_did(follower)

    register_device(target, ["follow"])

    ingest_op(follower, follower_key, "follow", target, %{
      "targetDid" => target,
      "visibility" => "federated"
    })

    await_flush()

    assert [%{token: token}] = TestSender.calls()
    assert token == "tok_#{target}"
  end

  test "a self-follow does not wake" do
    did = "did:plc:wake_selffollow_#{System.unique_integer([:positive])}"
    key = seed_did(did)

    register_device(did, ["follow"])
    ingest_op(did, key, "follow", did, %{"targetDid" => did, "visibility" => "federated"})

    await_flush()
    assert TestSender.calls() == []
  end

  test "mailbox delivery wakes the recipient but never the sender's own echo" do
    recipient = "did:plc:wake_recipient_#{System.unique_integer([:positive])}"
    sender = "did:plc:wake_sender_#{System.unique_integer([:positive])}"

    register_device(recipient, ["messenger"])

    deliver_message(sender, recipient)
    await_flush()

    assert [%{token: token}] = TestSender.calls()
    assert token == "tok_#{recipient}"

    # A self-send must not wake the sender's own device.
    TestSender.reset()
    register_device(sender, ["messenger"])
    deliver_message(sender, sender)
    await_flush()
    assert TestSender.calls() == []
  end

  test "category opt-out is respected" do
    author = "did:plc:wake_optout_#{System.unique_integer([:positive])}"
    replier = "did:plc:wake_optout_replier_#{System.unique_integer([:positive])}"
    author_key = seed_did(author)
    replier_key = seed_did(replier)
    thread_id = "thread-#{System.unique_integer([:positive])}"

    # Registered, but only follow wakes enabled — replies must not wake.
    register_device(author, ["follow"])

    ingest_op(author, author_key, "thread", thread_id, %{"title" => "hello"})

    ingest_op(replier, replier_key, "post", "post-#{System.unique_integer([:positive])}", %{
      "threadId" => thread_id,
      "body" => "a reply"
    })

    await_flush()
    assert TestSender.calls() == []
  end

  test "a burst inside the debounce window coalesces into one wake" do
    recipient = "did:plc:wake_debounce_#{System.unique_integer([:positive])}"
    sender = "did:plc:wake_debounce_sender_#{System.unique_integer([:positive])}"

    register_device(recipient, ["messenger"])

    deliver_message(sender, recipient)
    deliver_message(sender, recipient)
    await_flush()

    assert length(TestSender.calls()) == 1

    # After the window flushes, a new trigger opens a fresh window.
    deliver_message(sender, recipient)
    await_flush()
    assert length(TestSender.calls()) == 2
  end

  test "the wake payload is exactly the content-free sync hint" do
    recipient = "did:plc:wake_payload_#{System.unique_integer([:positive])}"
    sender = "did:plc:wake_payload_sender_#{System.unique_integer([:positive])}"

    register_device(recipient, ["messenger"])
    deliver_message(sender, recipient)
    await_flush()

    assert [%{payload: payload}] = TestSender.calls()
    assert payload == %{"hint" => "sync"}
    # No content fields can ride along: the hint is the entire payload.
    assert map_size(payload) == 1
    assert Map.keys(payload) == ["hint"]
  end
end
