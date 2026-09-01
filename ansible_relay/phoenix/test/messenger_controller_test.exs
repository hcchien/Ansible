defmodule AnsibleRelay.Web.MessengerControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{AbuseDetector, IdentityCache}
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

    case IdentityCache.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    AbuseDetector.reset()
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

  defp seed_did(did, public_key_hex) do
    :ok = IdentityCache.put(did, public_key_hex, "messenger:#{did}")
  end

  defp device_binding(subject_did, device_id, bundle) do
    %{
      "type" => "io.trisaura.messengerDeviceBinding",
      "version" => 1,
      "subject_did" => subject_did,
      "device_id" => device_id,
      "messenger_identity_key" => bundle["messenger_identity_key"],
      "signed_pre_key_id" => bundle["signed_pre_key_id"],
      "signed_pre_key" => bundle["signed_pre_key"]
    }
  end

  defp sign_device_binding(private_key, subject_did, device_id, bundle) do
    binding = device_binding(subject_did, device_id, bundle)
    {binding, sign(private_key, canonical_json(binding))}
  end

  defp sign_pre_keys(private_key, subject_did, device_id, pre_keys) do
    sign(
      private_key,
      canonical_json(%{
        "subject_did" => subject_did,
        "device_id" => device_id,
        "pre_keys" => pre_keys
      })
    )
  end

  defp sign_message(private_key, message) do
    sign(
      private_key,
      canonical_json(%{
        "message_id" => message["message_id"],
        "sender_did" => message["sender_did"],
        "sender_device_id" => message["sender_device_id"],
        "recipient_did" => message["recipient_did"],
        "recipient_device_id" => message["recipient_device_id"],
        "ciphertext_type" => message["ciphertext_type"],
        "ciphertext" => message["ciphertext"],
        "protocol_version" => message["protocol_version"],
        "created_at" => message["created_at"]
      })
    )
  end

  defp sign_message_batch(private_key, messages) do
    sign(private_key, canonical_json(%{"messages" => messages}))
  end

  defp sign_ack(private_key, message_id, recipient_did, recipient_device_id) do
    sign(
      private_key,
      canonical_json(%{
        "message_id" => message_id,
        "recipient_did" => recipient_did,
        "recipient_device_id" => recipient_device_id
      })
    )
  end

  defp sign_mailbox(private_key, recipient_did, recipient_device_id) do
    sign(
      private_key,
      canonical_json(%{
        "recipient_did" => recipient_did,
        "recipient_device_id" => recipient_device_id
      })
    )
  end

  defp pre_key_bundle_path(
         recipient_did,
         sender_did,
         sender_device_id,
         request_id,
         private_key
       ) do
    payload = %{
      "recipient_did" => recipient_did,
      "sender_did" => sender_did,
      "sender_device_id" => sender_device_id,
      "request_id" => request_id
    }

    query =
      payload
      |> Map.put("request_signature", sign(private_key, canonical_json(payload)))
      |> URI.encode_query()

    "/api/v1/messenger/pre-key-bundles/#{URI.encode(recipient_did)}?#{query}"
  end

  defp seed_store_device(subject_did, device_id) do
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
               "binding_signature" => "seed-signature"
             })
  end

  defp mailbox_path(recipient_did, recipient_device_id, signature, extra_query \\ %{}) do
    query =
      Map.merge(
        %{
          "recipient_did" => recipient_did,
          "recipient_device_id" => recipient_device_id,
          "request_signature" => signature
        },
        extra_query
      )

    "/api/v1/messenger/messages?" <> URI.encode_query(query)
  end

  test "rejects messenger device bindings with invalid signatures" do
    {bob_public_key, _bob_private_key} = ed25519_keypair()
    seed_did("did:plc:bob", bob_public_key)

    bundle = %{
      "messenger_identity_key" => "bob_identity_public",
      "signed_pre_key_id" => 42,
      "signed_pre_key" => "bob_signed_pre_key",
      "signed_pre_key_signature" => "bob_signed_pre_key_sig"
    }

    response =
      post_json("/api/v1/messenger/devices", %{
        "subject_did" => "did:plc:bob",
        "device_id" => "msgdev_bob",
        "bundle" => bundle,
        "binding" => device_binding("did:plc:bob", "msgdev_bob", bundle),
        "binding_signature" => "00"
      })

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "publishes bundle, consumes one pre-key, stores ciphertext, and acks delivery" do
    {bob_public_key, bob_private_key} = ed25519_keypair()
    {alice_public_key, alice_private_key} = ed25519_keypair()
    seed_did("did:plc:bob", bob_public_key)
    seed_did("did:plc:alice", alice_public_key)

    bob_bundle = %{
      "messenger_identity_key" => "bob_identity_public",
      "signed_pre_key_id" => 42,
      "signed_pre_key" => "bob_signed_pre_key",
      "signed_pre_key_signature" => "bob_signed_pre_key_sig",
      "expires_at" => "2027-06-13T00:00:00Z"
    }

    {bob_binding, bob_binding_signature} =
      sign_device_binding(bob_private_key, "did:plc:bob", "msgdev_bob", bob_bundle)

    publish =
      post_json("/api/v1/messenger/devices", %{
        "subject_did" => "did:plc:bob",
        "device_id" => "msgdev_bob",
        "bundle" => bob_bundle,
        "binding" => bob_binding,
        "binding_signature" => bob_binding_signature
      })

    assert publish.status == 201

    alice_bundle = %{
      "messenger_identity_key" => "alice_identity_public",
      "signed_pre_key_id" => 43,
      "signed_pre_key" => "alice_signed_pre_key",
      "signed_pre_key_signature" => "alice_signed_pre_key_sig"
    }

    {alice_binding, alice_binding_signature} =
      sign_device_binding(alice_private_key, "did:plc:alice", "msgdev_alice", alice_bundle)

    assert post_json("/api/v1/messenger/devices", %{
             "subject_did" => "did:plc:alice",
             "device_id" => "msgdev_alice",
             "bundle" => alice_bundle,
             "binding" => alice_binding,
             "binding_signature" => alice_binding_signature
           }).status == 201

    bob_pre_keys = [%{"pre_key_id" => 1001, "pre_key" => "bob_one_time_pre_key"}]

    prekeys =
      post_json("/api/v1/messenger/pre-keys", %{
        "subject_did" => "did:plc:bob",
        "device_id" => "msgdev_bob",
        "pre_keys" => bob_pre_keys,
        "request_signature" =>
          sign_pre_keys(bob_private_key, "did:plc:bob", "msgdev_bob", bob_pre_keys)
      })

    assert prekeys.status == 201

    anonymous_bundle = get_json("/api/v1/messenger/pre-key-bundles/did:plc:bob")
    assert anonymous_bundle.status == 422

    bundle_path =
      pre_key_bundle_path(
        "did:plc:bob",
        "did:plc:alice",
        "msgdev_alice",
        "msg_reservation_1",
        alice_private_key
      )

    bundle = get_json(bundle_path)
    assert bundle.status == 200
    assert %{"devices" => [device]} = Jason.decode!(bundle.resp_body)
    assert device["one_time_pre_key_id"] == 1001
    assert device["one_time_pre_key"] == "bob_one_time_pre_key"

    retry_bundle = get_json(bundle_path)
    assert %{"devices" => [retry_device]} = Jason.decode!(retry_bundle.resp_body)
    assert retry_device["one_time_pre_key_id"] == 1001

    second_bundle =
      get_json(
        pre_key_bundle_path(
          "did:plc:bob",
          "did:plc:alice",
          "msgdev_alice",
          "msg_reservation_2",
          alice_private_key
        )
      )

    assert second_bundle.status == 200
    assert %{"devices" => [second_device]} = Jason.decode!(second_bundle.resp_body)
    refute Map.has_key?(second_device, "one_time_pre_key_id")
    refute Map.has_key?(second_device, "one_time_pre_key")

    message = %{
      "message_id" => "msg_test",
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "ciphertext_type" => "pre_key_signal_message",
      "ciphertext" => "base64-ciphertext",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-05-14T00:00:00Z"
    }

    send_result =
      post_json(
        "/api/v1/messenger/messages",
        Map.put(message, "request_signature", sign_message(alice_private_key, message))
      )

    assert send_result.status == 202
    refute send_result.resp_body =~ "hello"

    mailbox =
      get_json(
        mailbox_path(
          "did:plc:bob",
          "msgdev_bob",
          sign_mailbox(bob_private_key, "did:plc:bob", "msgdev_bob")
        )
      )

    assert mailbox.status == 200

    assert %{"messages" => [message], "next_cursor" => cursor} =
             Jason.decode!(mailbox.resp_body)

    assert is_binary(cursor)
    assert message["message_id"] == "msg_test"
    assert message["ciphertext"] == "base64-ciphertext"

    ack =
      post_json("/api/v1/messenger/messages/msg_test/ack", %{
        "recipient_did" => "did:plc:bob",
        "recipient_device_id" => "msgdev_bob",
        "request_signature" => sign_ack(bob_private_key, "msg_test", "did:plc:bob", "msgdev_bob")
      })

    assert ack.status == 200

    empty_mailbox =
      get_json(
        mailbox_path(
          "did:plc:bob",
          "msgdev_bob",
          sign_mailbox(bob_private_key, "did:plc:bob", "msgdev_bob")
        )
      )

    assert %{"messages" => []} = Jason.decode!(empty_mailbox.resp_body)

    invalid_cursor =
      get_json(
        mailbox_path(
          "did:plc:bob",
          "msgdev_bob",
          sign_mailbox(bob_private_key, "did:plc:bob", "msgdev_bob"),
          %{"cursor" => "not-base64!"}
        )
      )

    assert invalid_cursor.status == 400
  end

  test "mailbox and ack authorization binds recipient DID to recipient device" do
    {bob_public_key, bob_private_key} = ed25519_keypair()
    {alice_public_key, alice_private_key} = ed25519_keypair()
    seed_did("did:plc:bob", bob_public_key)
    seed_did("did:plc:alice", alice_public_key)
    seed_store_device("did:plc:alice", "msgdev_alice")
    seed_store_device("did:plc:bob", "msgdev_bob")

    assert {:ok, _message} =
             MessengerStore.store_message(%{
               "message_id" => "msg_cross_did",
               "sender_did" => "did:plc:alice",
               "sender_device_id" => "msgdev_alice",
               "recipient_did" => "did:plc:bob",
               "recipient_device_id" => "msgdev_bob",
               "ciphertext_type" => "pre_key_signal_message",
               "ciphertext" => "base64-ciphertext",
               "protocol_version" => "signal-mvp-v1",
               "created_at" => "2026-05-14T00:00:00Z"
             })

    forged_mailbox =
      get_json(
        mailbox_path(
          "did:plc:alice",
          "msgdev_bob",
          sign_mailbox(alice_private_key, "did:plc:alice", "msgdev_bob")
        )
      )

    assert forged_mailbox.status == 403

    forged_ack =
      post_json("/api/v1/messenger/messages/msg_cross_did/ack", %{
        "recipient_did" => "did:plc:alice",
        "recipient_device_id" => "msgdev_bob",
        "request_signature" =>
          sign_ack(alice_private_key, "msg_cross_did", "did:plc:alice", "msgdev_bob")
      })

    assert forged_ack.status == 403
    assert Jason.decode!(forged_ack.resp_body)["error"] == "device_not_active"

    authorized_mailbox =
      get_json(
        mailbox_path(
          "did:plc:bob",
          "msgdev_bob",
          sign_mailbox(bob_private_key, "did:plc:bob", "msgdev_bob")
        )
      )

    assert %{"messages" => [%{"message_id" => "msg_cross_did"}]} =
             Jason.decode!(authorized_mailbox.resp_body)
  end

  test "device availability does not consume one-time pre-keys" do
    {bob_public_key, bob_private_key} = ed25519_keypair()
    seed_did("did:plc:bob", bob_public_key)

    bundle = %{
      "messenger_identity_key" => "bob_identity_public",
      "signed_pre_key_id" => 42,
      "signed_pre_key" => "bob_signed_pre_key",
      "signed_pre_key_signature" => "bob_signed_pre_key_sig"
    }

    {binding, binding_signature} =
      sign_device_binding(bob_private_key, "did:plc:bob", "msgdev_bob", bundle)

    assert post_json("/api/v1/messenger/devices", %{
             "subject_did" => "did:plc:bob",
             "device_id" => "msgdev_bob",
             "bundle" => bundle,
             "binding" => binding,
             "binding_signature" => binding_signature
           }).status == 201

    pre_keys = [%{"pre_key_id" => 1001, "pre_key" => "bob_one_time_pre_key"}]

    assert post_json("/api/v1/messenger/pre-keys", %{
             "subject_did" => "did:plc:bob",
             "device_id" => "msgdev_bob",
             "pre_keys" => pre_keys,
             "request_signature" =>
               sign_pre_keys(bob_private_key, "did:plc:bob", "msgdev_bob", pre_keys)
           }).status == 201

    availability = get_json("/api/v1/messenger/devices/did:plc:bob")
    assert availability.status == 200
    assert %{"devices" => [device]} = Jason.decode!(availability.resp_body)
    assert device["has_one_time_pre_keys"] == true
    refute Map.has_key?(device, "one_time_pre_key")
    refute Map.has_key?(device, "one_time_pre_key_id")

    consuming_bundle =
      get_json(
        pre_key_bundle_path(
          "did:plc:bob",
          "did:plc:bob",
          "msgdev_bob",
          "msg_self_reservation",
          bob_private_key
        )
      )

    assert %{"devices" => [reserved_device]} = Jason.decode!(consuming_bundle.resp_body)
    assert reserved_device["one_time_pre_key_id"] == 1001
  end

  test "pre-key reservations are rate limited per authenticated sender DID" do
    previous_policy = Application.get_env(:ansible_relay, :abuse_detector)

    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 2, refill_per_second: 0, suspension_ms: 60_000},
      peer: %{capacity: 20, refill_per_second: 20, suspension_ms: 60_000}
    })

    on_exit(fn -> Application.put_env(:ansible_relay, :abuse_detector, previous_policy) end)

    {alice_public_key, alice_private_key} = ed25519_keypair()
    seed_did("did:plc:alice", alice_public_key)
    seed_store_device("did:plc:alice", "msgdev_alice")
    seed_store_device("did:plc:bob", "msgdev_bob")

    assert {:ok, _pre_keys} =
             MessengerStore.publish_pre_keys(%{
               "subject_did" => "did:plc:bob",
               "device_id" => "msgdev_bob",
               "pre_keys" =>
                 for id <- 1..3 do
                   %{"pre_key_id" => id, "pre_key" => "bob_pre_key_#{id}"}
                 end
             })

    for request_id <- ["reservation_1", "reservation_2"] do
      response =
        get_json(
          pre_key_bundle_path(
            "did:plc:bob",
            "did:plc:alice",
            "msgdev_alice",
            request_id,
            alice_private_key
          )
        )

      assert response.status == 200
    end

    limited =
      get_json(
        pre_key_bundle_path(
          "did:plc:bob",
          "did:plc:alice",
          "msgdev_alice",
          "reservation_3",
          alice_private_key
        )
      )

    assert limited.status == 429
    assert Jason.decode!(limited.resp_body)["error"] == "rate_limited"
  end

  test "retries are idempotent and revoked devices cannot receive messages" do
    {alice_public_key, alice_private_key} = ed25519_keypair()
    {bob_public_key, bob_private_key} = ed25519_keypair()
    seed_did("did:plc:alice", alice_public_key)
    seed_did("did:plc:bob", bob_public_key)
    seed_store_device("did:plc:alice", "msgdev_alice")
    seed_store_device("did:plc:bob", "msgdev_bob")

    message = %{
      "message_id" => "msg_idempotent",
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "ciphertext_type" => "pre_key_signal_message",
      "ciphertext" => "opaque-ciphertext",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-09-01T00:00:00Z"
    }

    signed = Map.put(message, "request_signature", sign_message(alice_private_key, message))
    assert post_json("/api/v1/messenger/messages", signed).status == 202
    assert post_json("/api/v1/messenger/messages", signed).status == 202

    revoke_payload = %{
      "subject_did" => "did:plc:bob",
      "device_id" => "msgdev_bob",
      "reason" => "user_revoked"
    }

    revoke_signature = sign(bob_private_key, canonical_json(revoke_payload))

    assert post_json("/api/v1/messenger/devices/msgdev_bob/revoke", %{
             "subject_did" => "did:plc:bob",
             "reason" => "user_revoked",
             "request_signature" => revoke_signature
           }).status == 200

    assert get_json("/api/v1/messenger/devices/did:plc:bob").resp_body
           |> Jason.decode!()
           |> Map.fetch!("devices") == []

    mailbox =
      get_json(
        mailbox_path(
          "did:plc:bob",
          "msgdev_bob",
          sign_mailbox(bob_private_key, "did:plc:bob", "msgdev_bob")
        )
      )

    assert mailbox.status == 403
  end

  test "message ingestion is rate limited per operation without logging DID labels" do
    previous_policy = Application.get_env(:ansible_relay, :abuse_detector)

    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 1, refill_per_second: 0, suspension_ms: 60_000},
      peer: %{capacity: 20, refill_per_second: 20, suspension_ms: 60_000}
    })

    on_exit(fn -> Application.put_env(:ansible_relay, :abuse_detector, previous_policy) end)

    {alice_public_key, alice_private_key} = ed25519_keypair()
    seed_did("did:plc:alice", alice_public_key)
    seed_store_device("did:plc:alice", "msgdev_alice")
    seed_store_device("did:plc:bob", "msgdev_bob")

    base = %{
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "ciphertext_type" => "pre_key_signal_message",
      "ciphertext" => "opaque-ciphertext",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-09-01T00:00:00Z"
    }

    first = Map.put(base, "message_id", "msg_rate_1")
    second = Map.put(base, "message_id", "msg_rate_2")

    assert post_json(
             "/api/v1/messenger/messages",
             Map.put(first, "request_signature", sign_message(alice_private_key, first))
           ).status == 202

    limited =
      post_json(
        "/api/v1/messenger/messages",
        Map.put(second, "request_signature", sign_message(alice_private_key, second))
      )

    assert limited.status == 429
    assert Jason.decode!(limited.resp_body)["error"] == "rate_limited"

    metrics = AnsibleRelay.Metrics.render()
    assert metrics =~ ~s(messenger_rate_limit_rejections_total{operation="send_message")
    refute metrics =~ "did:plc:alice"
  end

  test "multi-device fanout is atomic when one envelope conflicts" do
    {alice_public_key, alice_private_key} = ed25519_keypair()
    seed_did("did:plc:alice", alice_public_key)
    seed_store_device("did:plc:alice", "msgdev_alice")
    seed_store_device("did:plc:bob", "msgdev_bob_phone")
    seed_store_device("did:plc:bob", "msgdev_bob_tablet")

    existing = %{
      "message_id" => "msg_batch_tablet",
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob_tablet",
      "ciphertext_type" => "pre_key_signal_message",
      "ciphertext" => "existing-ciphertext",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-09-01T00:00:00Z"
    }

    assert post_json(
             "/api/v1/messenger/messages",
             Map.put(existing, "request_signature", sign_message(alice_private_key, existing))
           ).status == 202

    messages = [
      %{
        "message_id" => "msg_batch_phone",
        "sender_did" => "did:plc:alice",
        "sender_device_id" => "msgdev_alice",
        "recipient_did" => "did:plc:bob",
        "recipient_device_id" => "msgdev_bob_phone",
        "ciphertext_type" => "pre_key_signal_message",
        "ciphertext" => "phone-ciphertext",
        "protocol_version" => "signal-mvp-v1",
        "created_at" => "2026-09-01T00:00:01Z"
      },
      Map.put(existing, "ciphertext", "conflicting-ciphertext")
    ]

    response =
      post_json("/api/v1/messenger/messages/batch", %{
        "messages" => messages,
        "request_signature" => sign_message_batch(alice_private_key, messages)
      })

    assert response.status == 409

    assert Repo.get_by(AnsibleRelay.MessengerStore.Message,
             message_id: "msg_batch_phone"
           ) == nil

    assert Repo.get_by!(AnsibleRelay.MessengerStore.Message,
             message_id: "msg_batch_tablet"
           ).ciphertext == "existing-ciphertext"
  end

  test "acked rows do not consume a mailbox page or advance its cursor" do
    seed_store_device("did:plc:alice", "msgdev_alice")
    seed_store_device("did:plc:bob", "msgdev_bob")

    base = %{
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "ciphertext_type" => "pre_key_signal_message",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-09-01T00:00:00Z"
    }

    assert {:ok, _} =
             MessengerStore.store_message(
               Map.merge(base, %{
                 "message_id" => "msg_already_acked",
                 "ciphertext" => "acked-ciphertext"
               })
             )

    assert {:ok, _} =
             MessengerStore.store_message(
               Map.merge(base, %{
                 "message_id" => "msg_still_pending",
                 "ciphertext" => "pending-ciphertext"
               })
             )

    assert {:ok, _} =
             MessengerStore.ack("msg_already_acked", "did:plc:bob", "msgdev_bob")

    assert {:ok, %{messages: [message], next_cursor: cursor}} =
             MessengerStore.mailbox("did:plc:bob", "msgdev_bob", nil, 1)

    assert message["message_id"] == "msg_still_pending"
    assert is_binary(cursor)
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
    {public_key, private_key} = ed25519_keypair()
    seed_did("did:plc:persisted", public_key)

    bundle = %{
      "messenger_identity_key" => "persisted_identity_public",
      "signed_pre_key_id" => 7,
      "signed_pre_key" => "persisted_signed_pre_key",
      "signed_pre_key_signature" => "persisted_signed_pre_key_sig"
    }

    {binding, binding_signature} =
      sign_device_binding(private_key, "did:plc:persisted", "msgdev_persisted", bundle)

    assert post_json("/api/v1/messenger/devices", %{
             "subject_did" => "did:plc:persisted",
             "device_id" => "msgdev_persisted",
             "bundle" => bundle,
             "binding" => binding,
             "binding_signature" => binding_signature
           }).status == 201

    pre_keys = [%{"pre_key_id" => 2001, "pre_key" => "persisted_one_time_key"}]

    assert post_json("/api/v1/messenger/pre-keys", %{
             "subject_did" => "did:plc:persisted",
             "device_id" => "msgdev_persisted",
             "pre_keys" => pre_keys,
             "request_signature" =>
               sign_pre_keys(private_key, "did:plc:persisted", "msgdev_persisted", pre_keys)
           }).status == 201

    MessengerStore |> Process.whereis() |> GenServer.stop(:normal)
    Process.sleep(50)

    bundle =
      get_json(
        pre_key_bundle_path(
          "did:plc:persisted",
          "did:plc:persisted",
          "msgdev_persisted",
          "msg_persisted_reservation",
          private_key
        )
      )

    assert bundle.status == 200
    assert %{"devices" => [device]} = Jason.decode!(bundle.resp_body)
    assert device["device_id"] == "msgdev_persisted"
    assert device["one_time_pre_key_id"] == 2001
    assert device["one_time_pre_key"] == "persisted_one_time_key"
  end
end
