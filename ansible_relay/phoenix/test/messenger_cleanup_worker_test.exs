defmodule AnsibleRelay.MessengerCleanupWorkerTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias AnsibleRelay.{MessengerCleanupWorker, MessengerStore, Repo}
  alias AnsibleRelay.MessengerStore.{Ack, Message}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    MessengerStore.reset()
    :ok
  end

  test "periodic worker deletes expired ciphertext and its ACK rows" do
    seed_device("did:plc:alice", "msgdev_alice")
    seed_device("did:plc:bob", "msgdev_bob")

    assert {:ok, _message} = MessengerStore.store_message(message("expired_message"))
    assert {:ok, _message} = MessengerStore.ack("expired_message", "did:plc:bob", "msgdev_bob")

    past = DateTime.add(DateTime.utc_now(), -60, :second)

    Message
    |> where([message], message.message_id == "expired_message")
    |> Repo.update_all(set: [expires_at: past])

    assert {:ok, 1} = MessengerCleanupWorker.run_once()
    assert Repo.get_by(Message, message_id: "expired_message") == nil
    assert Repo.get_by(Ack, message_id: "expired_message") == nil
  end

  test "purge batch size bounds work per transaction" do
    seed_device("did:plc:alice", "msgdev_alice")
    seed_device("did:plc:bob", "msgdev_bob")

    assert {:ok, _message} = MessengerStore.store_message(message("expired_one"))
    assert {:ok, _message} = MessengerStore.store_message(message("expired_two"))

    Message
    |> Repo.update_all(set: [expires_at: DateTime.add(DateTime.utc_now(), -60, :second)])

    assert MessengerStore.purge_expired_messages(1) == 1
    assert Repo.aggregate(Message, :count, :id) == 1
  end

  defp seed_device(subject_did, device_id) do
    assert {:ok, _device} =
             MessengerStore.publish_device(%{
               "subject_did" => subject_did,
               "device_id" => device_id,
               "bundle" => %{
                 "messenger_identity_key" => "#{device_id}_identity",
                 "signed_pre_key_id" => 1,
                 "signed_pre_key" => "#{device_id}_signed_pre_key",
                 "signed_pre_key_signature" => "#{device_id}_signature"
               },
               "binding" => %{},
               "binding_signature" => "test-signature"
             })
  end

  defp message(message_id) do
    %{
      "message_id" => message_id,
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "ciphertext_type" => "pre_key_signal_message",
      "ciphertext" => "opaque-ciphertext",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-09-01T00:00:00Z"
    }
  end
end
