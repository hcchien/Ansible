defmodule AnsibleRelay.Web.Controllers.MessengerController do
  @moduledoc """
  Encrypted messenger relay endpoints.

  These endpoints move only public bundle metadata and opaque ciphertext.
  """

  import Plug.Conn

  alias AnsibleRelay.{IdentityCache, MessengerStore}

  @plaintext_fields ["plaintext", "body", "message", "text"]

  def publish_device(conn, params) do
    with {:ok, subject_did} <- fetch_string(params, "subject_did"),
         {:ok, device_id} <- fetch_string(params, "device_id"),
         {:ok, bundle} <- fetch_map(params, "bundle"),
         {:ok, binding} <- fetch_map(params, "binding"),
         {:ok, binding_signature} <- fetch_string(params, "binding_signature"),
         :ok <- validate_device_binding(subject_did, device_id, bundle, binding),
         :ok <- verify_subject_signature(subject_did, binding, binding_signature),
         {:ok, device} <- MessengerStore.publish_device(params) do
      send_json(conn, 201, %{
        accepted: true,
        subject_did: device["subject_did"],
        device_id: device["device_id"]
      })
    else
      {:error, reason} ->
        send_messenger_error(conn, reason)
    end
  end

  def publish_pre_keys(conn, params) do
    with {:ok, subject_did} <- fetch_string(params, "subject_did"),
         {:ok, device_id} <- fetch_string(params, "device_id"),
         {:ok, pre_keys} <- fetch_list(params, "pre_keys"),
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
         {:ok, pre_keys} <- MessengerStore.publish_pre_keys(params) do
      send_json(conn, 201, %{accepted: true, published: length(pre_keys)})
    else
      {:error, reason} ->
        status = if reason == :device_not_found, do: 404, else: messenger_error_status(reason)
        send_json(conn, status, %{error: to_string(reason)})
    end
  end

  def pre_key_bundle(conn, %{"subject_did" => subject_did}) do
    case MessengerStore.reserve_bundle(subject_did) do
      {:ok, device} ->
        send_json(conn, 200, device)

      {:error, reason} ->
        send_json(conn, 422, %{error: to_string(reason)})
    end
  end

  def devices(conn, %{"subject_did" => subject_did}) do
    {:ok, body} = MessengerStore.device_availability(subject_did)
    send_json(conn, 200, body)
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
         {:ok, message} <- MessengerStore.store_message(params) do
      send_json(conn, 202, %{accepted: true, message_id: message["message_id"]})
    else
      {:error, reason} ->
        status = if reason == :duplicate_message, do: 409, else: messenger_error_status(reason)
        send_json(conn, status, %{error: to_string(reason)})
    end
  end

  def mailbox(conn, params) do
    with {:ok, recipient_did} <- fetch_string(params, "recipient_did"),
         {:ok, recipient_device_id} <- fetch_string(params, "recipient_device_id"),
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
         {:ok, messages} <- MessengerStore.mailbox(recipient_did, recipient_device_id) do
      send_json(conn, 200, %{messages: messages, next_cursor: nil})
    else
      {:error, reason} ->
        send_json(conn, messenger_error_status(reason), %{error: to_string(reason)})
    end
  end

  def ack(conn, %{"message_id" => message_id} = params) do
    with {:ok, recipient_did} <- fetch_string(params, "recipient_did"),
         {:ok, recipient_device_id} <- fetch_string(params, "recipient_device_id"),
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
         {:ok, message} <- MessengerStore.ack(message_id, recipient_did, recipient_device_id) do
      send_json(conn, 200, %{accepted: true, message_id: message["message_id"]})
    else
      {:error, :not_found} ->
        send_json(conn, 404, %{error: "not_found"})

      {:error, reason} ->
        send_json(conn, messenger_error_status(reason), %{error: to_string(reason)})
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

  defp verify_subject_signature(subject_did, payload, signature) do
    cond do
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

  defp send_messenger_error(conn, reason) do
    send_json(conn, messenger_error_status(reason), %{error: to_string(reason)})
  end

  defp messenger_error_status(:invalid_signature), do: 401
  defp messenger_error_status(:unverified_did), do: 401
  defp messenger_error_status(_reason), do: 422

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
