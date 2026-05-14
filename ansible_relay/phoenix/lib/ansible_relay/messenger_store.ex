defmodule AnsibleRelay.MessengerStore do
  @moduledoc """
  In-memory encrypted messenger relay store.

  The relay stores public device bundles, one-time pre-keys, and opaque
  ciphertext messages. It never accepts plaintext message fields.
  """

  use GenServer

  @plaintext_fields ["plaintext", "body", "message", "text"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def publish_device(attrs), do: GenServer.call(__MODULE__, {:publish_device, attrs})
  def publish_pre_keys(attrs), do: GenServer.call(__MODULE__, {:publish_pre_keys, attrs})
  def reserve_bundle(subject_did), do: GenServer.call(__MODULE__, {:reserve_bundle, subject_did})
  def store_message(attrs), do: GenServer.call(__MODULE__, {:store_message, attrs})

  def mailbox(recipient_device_id),
    do: GenServer.call(__MODULE__, {:mailbox, recipient_device_id})

  def ack(message_id, recipient_device_id),
    do: GenServer.call(__MODULE__, {:ack, message_id, recipient_device_id})

  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_opts) do
    {:ok, empty_state()}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, empty_state()}
  end

  def handle_call({:publish_device, attrs}, _from, state) do
    with {:ok, subject_did} <- fetch_string(attrs, "subject_did"),
         {:ok, device_id} <- fetch_string(attrs, "device_id"),
         {:ok, bundle} <- fetch_map(attrs, "bundle"),
         {:ok, messenger_identity_key} <- fetch_string(bundle, "messenger_identity_key"),
         {:ok, signed_pre_key_id} <- fetch_integer(bundle, "signed_pre_key_id"),
         {:ok, signed_pre_key} <- fetch_string(bundle, "signed_pre_key"),
         {:ok, signed_pre_key_signature} <- fetch_string(bundle, "signed_pre_key_signature"),
         {:ok, binding_signature} <- fetch_string(attrs, "binding_signature") do
      device = %{
        "subject_did" => subject_did,
        "device_id" => device_id,
        "messenger_identity_key" => messenger_identity_key,
        "signed_pre_key_id" => signed_pre_key_id,
        "signed_pre_key" => signed_pre_key,
        "signed_pre_key_signature" => signed_pre_key_signature,
        "expires_at" => Map.get(bundle, "expires_at"),
        "binding" => Map.get(attrs, "binding", %{}),
        "binding_signature" => binding_signature
      }

      state = put_in(state, [:devices, {subject_did, device_id}], device)
      {:reply, {:ok, device}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:publish_pre_keys, attrs}, _from, state) do
    with {:ok, subject_did} <- fetch_string(attrs, "subject_did"),
         {:ok, device_id} <- fetch_string(attrs, "device_id"),
         {:ok, pre_keys} <- fetch_list(attrs, "pre_keys"),
         :ok <- ensure_device_exists(state, subject_did, device_id),
         {:ok, normalized_pre_keys} <- normalize_pre_keys(pre_keys) do
      state =
        Enum.reduce(normalized_pre_keys, state, fn pre_key, acc ->
          put_in(acc, [:pre_keys, {subject_did, device_id, pre_key["pre_key_id"]}], pre_key)
        end)

      {:reply, {:ok, normalized_pre_keys}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reserve_bundle, subject_did}, _from, state) do
    {devices, state} =
      state.devices
      |> Map.values()
      |> Enum.filter(&(&1["subject_did"] == subject_did))
      |> Enum.sort_by(& &1["device_id"])
      |> Enum.map_reduce(state, fn device, acc ->
        {one_time_pre_key, acc} =
          pop_next_pre_key(acc, device["subject_did"], device["device_id"])

        {bundle_device(device, one_time_pre_key), acc}
      end)

    {:reply, {:ok, %{subject_did: subject_did, devices: devices}}, state}
  end

  def handle_call({:store_message, attrs}, _from, state) do
    with :ok <- reject_plaintext_fields(attrs),
         {:ok, message_id} <- fetch_string(attrs, "message_id"),
         {:ok, _sender_did} <- fetch_string(attrs, "sender_did"),
         {:ok, _sender_device_id} <- fetch_string(attrs, "sender_device_id"),
         {:ok, _recipient_did} <- fetch_string(attrs, "recipient_did"),
         {:ok, _recipient_device_id} <- fetch_string(attrs, "recipient_device_id"),
         {:ok, _ciphertext_type} <- fetch_string(attrs, "ciphertext_type"),
         {:ok, _ciphertext} <- fetch_string(attrs, "ciphertext"),
         {:ok, _protocol_version} <- fetch_string(attrs, "protocol_version"),
         :ok <- reject_duplicate_message(state, message_id) do
      message =
        attrs
        |> Map.take([
          "message_id",
          "sender_did",
          "sender_device_id",
          "recipient_did",
          "recipient_device_id",
          "ciphertext_type",
          "ciphertext",
          "protocol_version",
          "created_at"
        ])

      state = put_in(state, [:messages, message_id], message)
      {:reply, {:ok, message}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:mailbox, recipient_device_id}, _from, state) do
    messages =
      state.messages
      |> Map.values()
      |> Enum.filter(fn message ->
        message["recipient_device_id"] == recipient_device_id &&
          !MapSet.member?(state.acks, {message["message_id"], recipient_device_id})
      end)
      |> Enum.sort_by(&Map.get(&1, "created_at", ""))

    {:reply, {:ok, messages}, state}
  end

  def handle_call({:ack, message_id, recipient_device_id}, _from, state) do
    case Map.get(state.messages, message_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{"recipient_device_id" => ^recipient_device_id} = message ->
        state = %{state | acks: MapSet.put(state.acks, {message_id, recipient_device_id})}
        {:reply, {:ok, message}, state}

      _message ->
        {:reply, {:error, :recipient_mismatch}, state}
    end
  end

  defp empty_state do
    %{devices: %{}, pre_keys: %{}, messages: %{}, acks: MapSet.new()}
  end

  defp bundle_device(device, nil), do: device

  defp bundle_device(device, pre_key) do
    device
    |> Map.put("one_time_pre_key_id", pre_key["pre_key_id"])
    |> Map.put("one_time_pre_key", pre_key["pre_key"])
  end

  defp pop_next_pre_key(state, subject_did, device_id) do
    candidates =
      state.pre_keys
      |> Enum.filter(fn {{pre_key_subject_did, pre_key_device_id, _pre_key_id}, _pre_key} ->
        pre_key_subject_did == subject_did && pre_key_device_id == device_id
      end)
      |> Enum.sort_by(fn {{_subject_did, _device_id, pre_key_id}, _pre_key} -> pre_key_id end)

    case candidates do
      [] ->
        {nil, state}

      [{key, pre_key} | _rest] ->
        {pre_key, update_in(state, [:pre_keys], &Map.delete(&1, key))}
    end
  end

  defp ensure_device_exists(state, subject_did, device_id) do
    if Map.has_key?(state.devices, {subject_did, device_id}) do
      :ok
    else
      {:error, :device_not_found}
    end
  end

  defp normalize_pre_keys(pre_keys) do
    pre_keys
    |> Enum.reduce_while({:ok, []}, fn pre_key, {:ok, acc} ->
      with {:ok, pre_key_id} <- fetch_integer(pre_key, "pre_key_id"),
           {:ok, public_key} <- fetch_string(pre_key, "pre_key") do
        {:cont, {:ok, [%{"pre_key_id" => pre_key_id, "pre_key" => public_key} | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      error -> error
    end
  end

  defp reject_plaintext_fields(attrs) do
    if Enum.any?(@plaintext_fields, &Map.has_key?(attrs, &1)) do
      {:error, :plaintext_not_allowed}
    else
      :ok
    end
  end

  defp reject_duplicate_message(state, message_id) do
    if Map.has_key?(state.messages, message_id) do
      {:error, :duplicate_message}
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

  defp fetch_integer(attrs, key) do
    case Map.get(attrs, key) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :"#{key}_required"}
    end
  end
end
