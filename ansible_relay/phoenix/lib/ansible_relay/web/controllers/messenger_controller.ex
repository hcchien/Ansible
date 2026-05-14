defmodule AnsibleRelay.Web.Controllers.MessengerController do
  @moduledoc """
  Encrypted messenger relay endpoints.

  These endpoints move only public bundle metadata and opaque ciphertext.
  Signature verification is kept at the contract boundary for the next pass.
  """

  import Plug.Conn

  alias AnsibleRelay.MessengerStore

  def publish_device(conn, params) do
    case MessengerStore.publish_device(params) do
      {:ok, device} ->
        send_json(conn, 201, %{
          accepted: true,
          subject_did: device["subject_did"],
          device_id: device["device_id"]
        })

      {:error, reason} ->
        send_json(conn, 422, %{error: to_string(reason)})
    end
  end

  def publish_pre_keys(conn, params) do
    case MessengerStore.publish_pre_keys(params) do
      {:ok, pre_keys} ->
        send_json(conn, 201, %{accepted: true, published: length(pre_keys)})

      {:error, reason} ->
        status = if reason == :device_not_found, do: 404, else: 422
        send_json(conn, status, %{error: to_string(reason)})
    end
  end

  def pre_key_bundle(conn, %{"subject_did" => subject_did}) do
    case MessengerStore.reserve_bundle(subject_did) do
      {:ok, bundle} ->
        send_json(conn, 200, bundle)

      {:error, reason} ->
        send_json(conn, 422, %{error: to_string(reason)})
    end
  end

  def send_message(conn, params) do
    case MessengerStore.store_message(params) do
      {:ok, message} ->
        send_json(conn, 202, %{accepted: true, message_id: message["message_id"]})

      {:error, reason} ->
        status = if reason == :duplicate_message, do: 409, else: 422
        send_json(conn, status, %{error: to_string(reason)})
    end
  end

  def mailbox(conn, params) do
    case Map.get(params, "recipient_device_id") do
      recipient_device_id when is_binary(recipient_device_id) and recipient_device_id != "" ->
        {:ok, messages} = MessengerStore.mailbox(recipient_device_id)
        send_json(conn, 200, %{messages: messages, next_cursor: nil})

      _ ->
        send_json(conn, 422, %{error: "recipient_device_id_required"})
    end
  end

  def ack(conn, %{"message_id" => message_id} = params) do
    case Map.get(params, "recipient_device_id") do
      recipient_device_id when is_binary(recipient_device_id) and recipient_device_id != "" ->
        case MessengerStore.ack(message_id, recipient_device_id) do
          {:ok, message} ->
            send_json(conn, 200, %{accepted: true, message_id: message["message_id"]})

          {:error, :not_found} ->
            send_json(conn, 404, %{error: "not_found"})

          {:error, reason} ->
            send_json(conn, 422, %{error: to_string(reason)})
        end

      _ ->
        send_json(conn, 422, %{error: "recipient_device_id_required"})
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
