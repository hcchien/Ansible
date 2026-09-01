defmodule AnsibleRelay.MessengerPolicyTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.MessengerPolicy

  test "rejects oversized ciphertext and unsupported wire formats" do
    previous_limit = Application.get_env(:ansible_relay, :messenger_max_ciphertext_bytes)
    Application.put_env(:ansible_relay, :messenger_max_ciphertext_bytes, 4)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :messenger_max_ciphertext_bytes, previous_limit)
    end)

    message = valid_message()

    assert MessengerPolicy.validate_message(Map.put(message, "ciphertext", "12345")) ==
             {:error, :ciphertext_too_large}

    assert MessengerPolicy.validate_message(Map.put(message, "protocol_version", "future-v2")) ==
             {:error, :unsupported_protocol_version}

    assert MessengerPolicy.validate_message(Map.put(message, "ciphertext_type", "plaintext")) ==
             {:error, :unsupported_ciphertext_type}
  end

  test "bounds pre-key and multi-device batches" do
    previous_pre_keys = Application.get_env(:ansible_relay, :messenger_max_pre_keys_per_request)
    previous_messages = Application.get_env(:ansible_relay, :messenger_max_batch_messages)
    Application.put_env(:ansible_relay, :messenger_max_pre_keys_per_request, 1)
    Application.put_env(:ansible_relay, :messenger_max_batch_messages, 1)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :messenger_max_pre_keys_per_request, previous_pre_keys)
      Application.put_env(:ansible_relay, :messenger_max_batch_messages, previous_messages)
    end)

    pre_keys = [
      %{"pre_key_id" => 1, "pre_key" => "key-1"},
      %{"pre_key_id" => 2, "pre_key" => "key-2"}
    ]

    assert MessengerPolicy.validate_pre_keys(pre_keys) == {:error, :too_many_pre_keys}

    assert MessengerPolicy.validate_messages([valid_message(), valid_message()]) ==
             {:error, :too_many_messages}
  end

  defp valid_message do
    %{
      "message_id" => "msg_test",
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "ciphertext_type" => "pre_key_signal_message",
      "ciphertext" => "1234",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-09-01T00:00:00Z"
    }
  end
end
