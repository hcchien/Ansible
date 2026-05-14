defmodule AnsibleRelay.Web.MessengerControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.MessengerStore
  alias AnsibleRelay.Repo

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case MessengerStore.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> MessengerStore.reset()
    end

    :ok
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp get_json(path) do
    conn(:get, path)
    |> Router.call(@router_opts)
  end

  test "publishes bundle, consumes one pre-key, stores ciphertext, and acks delivery" do
    publish =
      post_json("/api/v1/messenger/devices", %{
        "subject_did" => "did:plc:bob",
        "device_id" => "msgdev_bob",
        "bundle" => %{
          "messenger_identity_key" => "bob_identity_public",
          "signed_pre_key_id" => 42,
          "signed_pre_key" => "bob_signed_pre_key",
          "signed_pre_key_signature" => "bob_signed_pre_key_sig",
          "expires_at" => "2026-06-13T00:00:00Z"
        },
        "binding" => %{"subject_did" => "did:plc:bob", "device_id" => "msgdev_bob"},
        "binding_signature" => "dev-signature"
      })

    assert publish.status == 201

    prekeys =
      post_json("/api/v1/messenger/pre-keys", %{
        "subject_did" => "did:plc:bob",
        "device_id" => "msgdev_bob",
        "pre_keys" => [%{"pre_key_id" => 1001, "pre_key" => "bob_one_time_pre_key"}],
        "request_signature" => "dev-signature"
      })

    assert prekeys.status == 201

    bundle = get_json("/api/v1/messenger/pre-key-bundles/did:plc:bob")
    assert bundle.status == 200
    assert %{"devices" => [device]} = Jason.decode!(bundle.resp_body)
    assert device["one_time_pre_key_id"] == 1001
    assert device["one_time_pre_key"] == "bob_one_time_pre_key"

    second_bundle = get_json("/api/v1/messenger/pre-key-bundles/did:plc:bob")
    assert second_bundle.status == 200
    assert %{"devices" => [second_device]} = Jason.decode!(second_bundle.resp_body)
    refute Map.has_key?(second_device, "one_time_pre_key_id")
    refute Map.has_key?(second_device, "one_time_pre_key")

    send_result =
      post_json("/api/v1/messenger/messages", %{
        "message_id" => "msg_test",
        "sender_did" => "did:plc:alice",
        "sender_device_id" => "msgdev_alice",
        "recipient_did" => "did:plc:bob",
        "recipient_device_id" => "msgdev_bob",
        "ciphertext_type" => "pre_key_signal_message",
        "ciphertext" => "base64-ciphertext",
        "protocol_version" => "signal-mvp-v1",
        "created_at" => "2026-05-14T00:00:00Z",
        "request_signature" => "dev-signature"
      })

    assert send_result.status == 202
    refute send_result.resp_body =~ "hello"

    mailbox = get_json("/api/v1/messenger/messages?recipient_device_id=msgdev_bob")
    assert mailbox.status == 200
    assert %{"messages" => [message]} = Jason.decode!(mailbox.resp_body)
    assert message["message_id"] == "msg_test"
    assert message["ciphertext"] == "base64-ciphertext"

    ack =
      post_json("/api/v1/messenger/messages/msg_test/ack", %{
        "recipient_did" => "did:plc:bob",
        "recipient_device_id" => "msgdev_bob",
        "request_signature" => "dev-signature"
      })

    assert ack.status == 200

    empty_mailbox = get_json("/api/v1/messenger/messages?recipient_device_id=msgdev_bob")
    assert %{"messages" => []} = Jason.decode!(empty_mailbox.resp_body)
  end

  test "rejects message payloads that contain plaintext-shaped fields" do
    response =
      post_json("/api/v1/messenger/messages", %{
        "message_id" => "msg_plaintext",
        "sender_did" => "did:plc:alice",
        "sender_device_id" => "msgdev_alice",
        "recipient_did" => "did:plc:bob",
        "recipient_device_id" => "msgdev_bob",
        "ciphertext_type" => "pre_key_signal_message",
        "ciphertext" => "base64-ciphertext",
        "protocol_version" => "signal-mvp-v1",
        "plaintext" => "hello bob",
        "request_signature" => "dev-signature"
      })

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "plaintext_not_allowed"
  end

  test "messenger data survives store process restart" do
    assert post_json("/api/v1/messenger/devices", %{
             "subject_did" => "did:plc:persisted",
             "device_id" => "msgdev_persisted",
             "bundle" => %{
               "messenger_identity_key" => "persisted_identity_public",
               "signed_pre_key_id" => 7,
               "signed_pre_key" => "persisted_signed_pre_key",
               "signed_pre_key_signature" => "persisted_signed_pre_key_sig"
             },
             "binding" => %{
               "subject_did" => "did:plc:persisted",
               "device_id" => "msgdev_persisted"
             },
             "binding_signature" => "dev-signature"
           }).status == 201

    assert post_json("/api/v1/messenger/pre-keys", %{
             "subject_did" => "did:plc:persisted",
             "device_id" => "msgdev_persisted",
             "pre_keys" => [%{"pre_key_id" => 2001, "pre_key" => "persisted_one_time_key"}],
             "request_signature" => "dev-signature"
           }).status == 201

    MessengerStore |> Process.whereis() |> GenServer.stop(:normal)
    Process.sleep(50)

    bundle = get_json("/api/v1/messenger/pre-key-bundles/did:plc:persisted")
    assert bundle.status == 200
    assert %{"devices" => [device]} = Jason.decode!(bundle.resp_body)
    assert device["device_id"] == "msgdev_persisted"
    assert device["one_time_pre_key_id"] == 2001
    assert device["one_time_pre_key"] == "persisted_one_time_key"
  end
end
