defmodule AnsibleRelay.Web.Controllers.MessengerController do
  @moduledoc """
  Encrypted messenger relay endpoints.

  These endpoints move only public bundle metadata and opaque ciphertext.
  """

  import Plug.Conn

  alias AnsibleRelay.{AbuseDetector, IdentityCache, MessengerPolicy, MessengerStore, Metrics}

  @plaintext_fields ["plaintext", "body", "message", "text"]

  def publish_device(conn, params) do
    with {:ok, subject_did} <- fetch_string(params, "subject_did"),
         {:ok, device_id} <- fetch_string(params, "device_id"),
         {:ok, bundle} <- fetch_map(params, "bundle"),
         {:ok, binding} <- fetch_map(params, "binding"),
         {:ok, binding_signature} <- fetch_string(params, "binding_signature"),
         :ok <- MessengerPolicy.validate_device(subject_did, device_id, bundle),
         :ok <- validate_device_binding(subject_did, device_id, bundle, binding),
         :ok <- verify_subject_signature(subject_did, binding, binding_signature),
         :ok <- check_did_rate_limit("publish_device", subject_did),
         {:ok, device} <- MessengerStore.publish_device(params) do
      record_success("publish_device")

      send_json(conn, 201, %{
        accepted: true,
        subject_did: device["subject_did"],
        device_id: device["device_id"]
      })
    else
      error ->
        send_messenger_error(conn, "publish_device", error)
    end
  end

  def publish_pre_keys(conn, params) do
    with {:ok, subject_did} <- fetch_string(params, "subject_did"),
         {:ok, device_id} <- fetch_string(params, "device_id"),
         {:ok, pre_keys} <- fetch_list(params, "pre_keys"),
         :ok <- MessengerPolicy.validate_database_strings([subject_did, device_id]),
         :ok <- MessengerPolicy.validate_pre_keys(pre_keys),
         {:ok, request_signature} <- fetch_string(params, "request_signature"),
         :ok <-
           verify_subject_signature(
             subject_did,
             %{
               "subject_did" => subject_did,
               "device_id" => device_id,
               "pre_keys" => pre_keys
             },
             request_signature
           ),
         :ok <- check_did_rate_limit("publish_pre_keys", subject_did),
         {:ok, pre_keys} <- MessengerStore.publish_pre_keys(params) do
      record_success("publish_pre_keys")
      send_json(conn, 201, %{accepted: true, published: length(pre_keys)})
    else
      error ->
        send_messenger_error(conn, "publish_pre_keys", error)
    end
  end

  def pre_key_bundle(conn, %{"subject_did" => recipient_did} = params) do
    with {:ok, sender_did} <- fetch_string(params, "sender_did"),
         {:ok, sender_device_id} <- fetch_string(params, "sender_device_id"),
         {:ok, request_id} <- fetch_string(params, "request_id"),
         :ok <-
           MessengerPolicy.validate_database_strings([
             recipient_did,
             sender_did,
             sender_device_id,
             request_id
           ]),
         {:ok, request_signature} <- fetch_string(params, "request_signature"),
         :ok <-
           verify_subject_signature(
             sender_did,
             %{
               "recipient_did" => recipient_did,
               "sender_did" => sender_did,
               "sender_device_id" => sender_device_id,
               "request_id" => request_id
             },
             request_signature
           ),
         :ok <- check_did_rate_limit("reserve_pre_key", sender_did),
         {:ok, device} <-
           MessengerStore.reserve_bundle(
             recipient_did,
             sender_did,
             sender_device_id,
             request_id
           ) do
      record_success("reserve_pre_key")
      send_json(conn, 200, device)
    else
      error ->
        send_messenger_error(conn, "reserve_pre_key", error)
    end
  end

  def devices(conn, %{"subject_did" => subject_did}) do
    with :ok <- MessengerPolicy.validate_database_strings([subject_did]),
         :ok <- check_peer_rate_limit("device_availability", peer_key(conn)),
         {:ok, body} <- MessengerStore.device_availability(subject_did) do
      record_success("device_availability")
      send_json(conn, 200, body)
    else
      error -> send_messenger_error(conn, "device_availability", error)
    end
  end

  def revoke_device(conn, %{"device_id" => device_id} = params) do
    with {:ok, subject_did} <- fetch_string(params, "subject_did"),
         {:ok, reason} <- fetch_string(params, "reason"),
         :ok <- MessengerPolicy.validate_database_strings([subject_did, device_id, reason]),
         {:ok, request_signature} <- fetch_string(params, "request_signature"),
         :ok <-
           verify_subject_signature(
             subject_did,
             %{"subject_did" => subject_did, "device_id" => device_id, "reason" => reason},
             request_signature
           ),
         :ok <- check_did_rate_limit("revoke_device", subject_did),
         {:ok, _device} <- MessengerStore.revoke_device(subject_did, device_id, reason) do
      record_success("revoke_device")
      send_json(conn, 200, %{accepted: true, device_id: device_id})
    else
      error -> send_messenger_error(conn, "revoke_device", error)
    end
  end

  def send_message(conn, params) do
    with :ok <- reject_plaintext_fields(params),
         {:ok, message_id} <- fetch_string(params, "message_id"),
         {:ok, sender_did} <- fetch_string(params, "sender_did"),
         {:ok, sender_device_id} <- fetch_string(params, "sender_device_id"),
         {:ok, recipient_did} <- fetch_string(params, "recipient_did"),
         {:ok, recipient_device_id} <- fetch_string(params, "recipient_device_id"),
         {:ok, ciphertext_type} <- fetch_string(params, "ciphertext_type"),
         {:ok, ciphertext} <- fetch_string(params, "ciphertext"),
         {:ok, protocol_version} <- fetch_string(params, "protocol_version"),
         {:ok, created_at} <- fetch_string(params, "created_at"),
         :ok <- MessengerPolicy.validate_message(params),
         {:ok, request_signature} <- fetch_string(params, "request_signature"),
         :ok <-
           verify_subject_signature(
             sender_did,
             %{
               "message_id" => message_id,
               "sender_did" => sender_did,
               "sender_device_id" => sender_device_id,
               "recipient_did" => recipient_did,
               "recipient_device_id" => recipient_device_id,
               "ciphertext_type" => ciphertext_type,
               "ciphertext" => ciphertext,
               "protocol_version" => protocol_version,
               "created_at" => created_at
             },
             request_signature
           ),
         :ok <- check_did_rate_limit("send_message", sender_did),
         {:ok, message} <- MessengerStore.store_message(params) do
      record_success("send_message")
      Metrics.inc("messenger_messages_accepted_total")
      send_json(conn, 202, %{accepted: true, message_id: message["message_id"]})
    else
      error ->
        send_messenger_error(conn, "send_message", error)
    end
  end

  def send_message_batch(conn, params) do
    with {:ok, messages} <- fetch_list(params, "messages"),
         :ok <- MessengerPolicy.validate_messages(messages),
         {:ok, sender_did} <- validate_message_batch(messages),
         {:ok, request_signature} <- fetch_string(params, "request_signature"),
         :ok <-
           verify_subject_signature(
             sender_did,
             %{"messages" => messages},
             request_signature
           ),
         :ok <- check_did_rate_limit("send_message_batch", sender_did),
         {:ok, stored} <- MessengerStore.store_messages(messages) do
      record_success("send_message_batch")
      Metrics.inc("messenger_messages_accepted_total", %{}, length(stored))

      send_json(conn, 202, %{
        accepted: true,
        message_ids: Enum.map(stored, & &1["message_id"])
      })
    else
      error ->
        send_messenger_error(conn, "send_message_batch", error)
    end
  end

  def mailbox(conn, params) do
    with {:ok, recipient_did} <- fetch_string(params, "recipient_did"),
         {:ok, recipient_device_id} <- fetch_string(params, "recipient_device_id"),
         :ok <-
           MessengerPolicy.validate_database_strings([recipient_did, recipient_device_id]),
         {:ok, request_signature} <- fetch_string(params, "request_signature"),
         :ok <-
           verify_subject_signature(
             recipient_did,
             %{
               "recipient_did" => recipient_did,
               "recipient_device_id" => recipient_device_id
             },
             request_signature
           ),
         :ok <- check_did_rate_limit("mailbox", recipient_did),
         {:ok, result} <-
           Metrics.time("messenger_mailbox_duration_seconds", fn ->
             MessengerStore.mailbox(
               recipient_did,
               recipient_device_id,
               Map.get(params, "cursor")
             )
           end) do
      record_success("mailbox")
      Metrics.inc("messenger_mailbox_messages_returned_total", %{}, length(result.messages))
      send_json(conn, 200, result)
    else
      error ->
        send_messenger_error(conn, "mailbox", error)
    end
  end

  def ack(conn, %{"message_id" => message_id} = params) do
    with {:ok, recipient_did} <- fetch_string(params, "recipient_did"),
         {:ok, recipient_device_id} <- fetch_string(params, "recipient_device_id"),
         :ok <-
           MessengerPolicy.validate_database_strings([
             message_id,
             recipient_did,
             recipient_device_id
           ]),
         {:ok, request_signature} <- fetch_string(params, "request_signature"),
         :ok <-
           verify_subject_signature(
             recipient_did,
             %{
               "message_id" => message_id,
               "recipient_did" => recipient_did,
               "recipient_device_id" => recipient_device_id
             },
             request_signature
           ),
         :ok <- check_did_rate_limit("ack", recipient_did),
         {:ok, message} <- MessengerStore.ack(message_id, recipient_did, recipient_device_id) do
      record_success("ack")
      Metrics.inc("messenger_acks_total")
      send_json(conn, 200, %{accepted: true, message_id: message["message_id"]})
    else
      error ->
        send_messenger_error(conn, "ack", error)
    end
  end

  defp validate_device_binding(subject_did, device_id, bundle, binding) do
    expected = %{
      "type" => "io.trisaura.messengerDeviceBinding",
      "version" => 1,
      "subject_did" => subject_did,
      "device_id" => device_id,
      "messenger_identity_key" => Map.get(bundle, "messenger_identity_key"),
      "signed_pre_key_id" => Map.get(bundle, "signed_pre_key_id"),
      "signed_pre_key" => Map.get(bundle, "signed_pre_key")
    }

    if binding == expected, do: :ok, else: {:error, :binding_mismatch}
  end

  defp validate_message_batch([first | _rest] = messages) when is_map(first) do
    with {:ok, sender_did} <- fetch_string(first, "sender_did"),
         true <- Enum.all?(messages, &is_map/1),
         true <- Enum.all?(messages, &(Map.get(&1, "sender_did") == sender_did)) do
      {:ok, sender_did}
    else
      _ -> {:error, :message_batch_sender_mismatch}
    end
  end

  defp validate_message_batch(_messages), do: {:error, :messages_required}

  defp verify_subject_signature(subject_did, payload, signature) do
    cond do
      byte_size(signature) > 4_096 -> {:error, :signature_too_large}
      not IdentityCache.verified?(subject_did) -> {:error, :unverified_did}
      IdentityCache.verify_signature(subject_did, canonical_json(payload), signature) -> :ok
      true -> {:error, :invalid_signature}
    end
  end

  defp reject_plaintext_fields(attrs) do
    if Enum.any?(@plaintext_fields, &Map.has_key?(attrs, &1)) do
      {:error, :plaintext_not_allowed}
    else
      :ok
    end
  end

  defp fetch_map(attrs, key) do
    case Map.get(attrs, key) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, :"#{key}_required"}
    end
  end

  defp fetch_list(attrs, key) do
    case Map.get(attrs, key) do
      value when is_list(value) -> {:ok, value}
      _ -> {:error, :"#{key}_required"}
    end
  end

  defp fetch_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, :"#{key}_required"}, else: {:ok, value}

      _ ->
        {:error, :"#{key}_required"}
    end
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

  defp check_did_rate_limit(operation, did) do
    case AbuseDetector.check_did("messenger:#{operation}:#{did}") do
      :ok ->
        :ok

      {:error, :rate_limited, _detail} = error ->
        Metrics.inc("messenger_rate_limit_rejections_total", %{operation: operation})
        error
    end
  end

  defp check_peer_rate_limit(operation, peer) do
    case AbuseDetector.check_peer("messenger:#{operation}:#{peer}") do
      :ok ->
        :ok

      {:error, :rate_limited, _detail} = error ->
        Metrics.inc("messenger_rate_limit_rejections_total", %{operation: operation})
        error
    end
  end

  defp peer_key(%Plug.Conn{remote_ip: remote_ip}) do
    remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp record_success(operation) do
    Metrics.inc("messenger_requests_total", %{operation: operation, result: "success"})
  end

  defp send_messenger_error(conn, operation, {:error, :rate_limited, detail}) do
    Metrics.inc("messenger_requests_total", %{operation: operation, result: "rate_limited"})
    send_json(conn, 429, %{error: "rate_limited", detail: detail})
  end

  defp send_messenger_error(conn, operation, {:error, reason}) do
    Metrics.inc("messenger_requests_total", %{operation: operation, result: "error"})
    send_json(conn, messenger_error_status(reason), %{error: to_string(reason)})
  end

  defp messenger_error_status(:invalid_signature), do: 401
  defp messenger_error_status(:unverified_did), do: 401
  defp messenger_error_status(:device_not_active), do: 403
  defp messenger_error_status(:message_id_conflict), do: 409
  defp messenger_error_status(:invalid_cursor), do: 400
  defp messenger_error_status(:device_not_found), do: 404
  defp messenger_error_status(:not_found), do: 404
  defp messenger_error_status(_reason), do: 422

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
