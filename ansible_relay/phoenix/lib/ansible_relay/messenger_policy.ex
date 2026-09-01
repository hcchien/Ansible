defmodule AnsibleRelay.MessengerPolicy do
  @moduledoc """
  Bounded input policy for the opaque Messenger transport.

  Limits are enforced independently of Plug's global body limit so Messenger
  cannot consume an unbounded amount of database or signature-verification
  work while other Relay APIs retain their existing payload contracts.
  """

  @app :ansible_relay
  @protocol_version "signal-mvp-v1"
  @ciphertext_type "pre_key_signal_message"

  @default_max_pre_keys 100
  @default_max_batch_messages 32
  @default_max_ciphertext_bytes 131_072
  @default_max_key_bytes 4_096
  @max_database_string_bytes 255

  @message_database_fields ~w(
    message_id sender_did sender_device_id recipient_did recipient_device_id
    ciphertext_type protocol_version
  )

  def validate_device(subject_did, device_id, bundle) when is_map(bundle) do
    with :ok <- validate_database_strings([subject_did, device_id]),
         :ok <- validate_key(Map.get(bundle, "messenger_identity_key")),
         :ok <- validate_key(Map.get(bundle, "signed_pre_key")),
         :ok <- validate_key(Map.get(bundle, "signed_pre_key_signature")),
         :ok <- validate_non_negative_integer(Map.get(bundle, "signed_pre_key_id")),
         :ok <- validate_optional_timestamp(Map.get(bundle, "expires_at")) do
      :ok
    end
  end

  def validate_device(_subject_did, _device_id, _bundle), do: {:error, :invalid_device_bundle}

  def validate_database_strings(values) when is_list(values) do
    if Enum.all?(values, &bounded_database_string?/1) do
      :ok
    else
      {:error, :identifier_too_large}
    end
  end

  def validate_pre_keys(pre_keys) when is_list(pre_keys) do
    cond do
      pre_keys == [] ->
        {:error, :pre_keys_required}

      length(pre_keys) > max_pre_keys() ->
        {:error, :too_many_pre_keys}

      Enum.all?(pre_keys, &valid_pre_key?/1) ->
        :ok

      true ->
        {:error, :invalid_pre_key}
    end
  end

  def validate_pre_keys(_pre_keys), do: {:error, :pre_keys_required}

  def validate_messages(messages) when is_list(messages) do
    cond do
      messages == [] ->
        {:error, :messages_required}

      length(messages) > max_batch_messages() ->
        {:error, :too_many_messages}

      true ->
        Enum.reduce_while(messages, :ok, fn message, :ok ->
          case validate_message(message) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
    end
  end

  def validate_messages(_messages), do: {:error, :messages_required}

  def validate_message(message) when is_map(message) do
    with :ok <- validate_message_database_fields(message),
         :ok <- require_protocol(message),
         :ok <- require_ciphertext_type(message),
         :ok <- require_bounded_ciphertext(message),
         :ok <- require_iso8601_timestamp(message) do
      :ok
    end
  end

  def validate_message(_message), do: {:error, :invalid_message}

  defp valid_pre_key?(%{"pre_key_id" => id, "pre_key" => key}) do
    is_integer(id) and id >= 0 and is_binary(key) and byte_size(key) > 0 and
      byte_size(key) <= max_key_bytes()
  end

  defp valid_pre_key?(_pre_key), do: false

  defp validate_message_database_fields(message) do
    values = Enum.map(@message_database_fields, &Map.get(message, &1))
    validate_database_strings(values)
  end

  defp bounded_database_string?(value) when is_binary(value) do
    byte_size(value) > 0 and byte_size(value) <= @max_database_string_bytes
  end

  defp bounded_database_string?(_value), do: false

  defp validate_key(value) when is_binary(value) do
    if byte_size(value) > 0 and byte_size(value) <= max_key_bytes() do
      :ok
    else
      {:error, :invalid_device_key}
    end
  end

  defp validate_key(_value), do: {:error, :invalid_device_key}

  defp validate_non_negative_integer(value) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative_integer(_value), do: {:error, :invalid_signed_pre_key_id}

  defp validate_optional_timestamp(nil), do: :ok
  defp validate_optional_timestamp(""), do: :ok

  defp validate_optional_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _timestamp, _offset} -> :ok
      _ -> {:error, :invalid_device_expiry}
    end
  end

  defp validate_optional_timestamp(_value), do: {:error, :invalid_device_expiry}

  defp require_protocol(%{"protocol_version" => @protocol_version}), do: :ok
  defp require_protocol(_message), do: {:error, :unsupported_protocol_version}

  defp require_ciphertext_type(%{"ciphertext_type" => @ciphertext_type}), do: :ok
  defp require_ciphertext_type(_message), do: {:error, :unsupported_ciphertext_type}

  defp require_bounded_ciphertext(%{"ciphertext" => ciphertext}) when is_binary(ciphertext) do
    cond do
      byte_size(ciphertext) == 0 -> {:error, :ciphertext_required}
      byte_size(ciphertext) > max_ciphertext_bytes() -> {:error, :ciphertext_too_large}
      true -> :ok
    end
  end

  defp require_bounded_ciphertext(_message), do: {:error, :ciphertext_required}

  defp require_iso8601_timestamp(%{"created_at" => created_at}) when is_binary(created_at) do
    case DateTime.from_iso8601(created_at) do
      {:ok, _timestamp, _offset} -> :ok
      _ -> {:error, :invalid_created_at}
    end
  end

  defp require_iso8601_timestamp(_message), do: {:error, :created_at_required}

  defp max_pre_keys do
    Application.get_env(@app, :messenger_max_pre_keys_per_request, @default_max_pre_keys)
  end

  defp max_batch_messages do
    Application.get_env(@app, :messenger_max_batch_messages, @default_max_batch_messages)
  end

  defp max_ciphertext_bytes do
    Application.get_env(@app, :messenger_max_ciphertext_bytes, @default_max_ciphertext_bytes)
  end

  defp max_key_bytes do
    Application.get_env(@app, :messenger_max_key_bytes, @default_max_key_bytes)
  end
end
