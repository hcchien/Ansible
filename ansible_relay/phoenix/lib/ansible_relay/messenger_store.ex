defmodule AnsibleRelay.MessengerStore do
  @moduledoc """
  Ecto-backed encrypted messenger relay store.

  The relay stores public device bundles, one-time pre-keys, and opaque
  ciphertext messages. It never accepts plaintext message fields.
  """

  use GenServer
  import Ecto.Query

  alias AnsibleRelay.Repo

  @plaintext_fields ["plaintext", "body", "message", "text"]

  defmodule Device do
    use Ecto.Schema

    @timestamps_opts [type: :utc_datetime_usec]
    schema "messenger_devices" do
      field(:subject_did, :string)
      field(:device_id, :string)
      field(:messenger_identity_key, :string)
      field(:signed_pre_key_id, :integer)
      field(:signed_pre_key, :string)
      field(:signed_pre_key_signature, :string)
      field(:expires_at, :string)
      field(:binding, :map, default: %{})
      field(:binding_signature, :string)

      timestamps()
    end
  end

  defmodule PreKey do
    use Ecto.Schema

    @timestamps_opts [type: :utc_datetime_usec]
    schema "messenger_pre_keys" do
      field(:subject_did, :string)
      field(:device_id, :string)
      field(:pre_key_id, :integer)
      field(:pre_key, :string)
      field(:reserved_at, :utc_datetime_usec)

      timestamps()
    end
  end

  defmodule Message do
    use Ecto.Schema

    @timestamps_opts [type: :utc_datetime_usec]
    schema "messenger_messages" do
      field(:message_id, :string)
      field(:sender_did, :string)
      field(:sender_device_id, :string)
      field(:recipient_did, :string)
      field(:recipient_device_id, :string)
      field(:ciphertext_type, :string)
      field(:ciphertext, :string)
      field(:protocol_version, :string)
      field(:message_created_at, :string)

      timestamps()
    end
  end

  defmodule Ack do
    use Ecto.Schema

    @timestamps_opts [type: :utc_datetime_usec]
    schema "messenger_message_acks" do
      field(:message_id, :string)
      field(:recipient_device_id, :string)
      field(:acked_at, :utc_datetime_usec)

      timestamps()
    end
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def publish_device(attrs) do
    with {:ok, subject_did} <- fetch_string(attrs, "subject_did"),
         {:ok, device_id} <- fetch_string(attrs, "device_id"),
         {:ok, bundle} <- fetch_map(attrs, "bundle"),
         {:ok, messenger_identity_key} <- fetch_string(bundle, "messenger_identity_key"),
         {:ok, signed_pre_key_id} <- fetch_integer(bundle, "signed_pre_key_id"),
         {:ok, signed_pre_key} <- fetch_string(bundle, "signed_pre_key"),
         {:ok, signed_pre_key_signature} <- fetch_string(bundle, "signed_pre_key_signature"),
         {:ok, binding_signature} <- fetch_string(attrs, "binding_signature") do
      now = now()

      changes = %{
        subject_did: subject_did,
        device_id: device_id,
        messenger_identity_key: messenger_identity_key,
        signed_pre_key_id: signed_pre_key_id,
        signed_pre_key: signed_pre_key,
        signed_pre_key_signature: signed_pre_key_signature,
        expires_at: Map.get(bundle, "expires_at"),
        binding: Map.get(attrs, "binding", %{}),
        binding_signature: binding_signature,
        inserted_at: now,
        updated_at: now
      }

      {:ok, device} =
        %Device{}
        |> struct(changes)
        |> Repo.insert(
          on_conflict: [
            set: [
              messenger_identity_key: messenger_identity_key,
              signed_pre_key_id: signed_pre_key_id,
              signed_pre_key: signed_pre_key,
              signed_pre_key_signature: signed_pre_key_signature,
              expires_at: Map.get(bundle, "expires_at"),
              binding: Map.get(attrs, "binding", %{}),
              binding_signature: binding_signature,
              updated_at: now
            ]
          ],
          conflict_target: [:subject_did, :device_id],
          returning: true
        )

      {:ok, device_map(device)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def publish_pre_keys(attrs) do
    with {:ok, subject_did} <- fetch_string(attrs, "subject_did"),
         {:ok, device_id} <- fetch_string(attrs, "device_id"),
         {:ok, pre_keys} <- fetch_list(attrs, "pre_keys"),
         :ok <- ensure_device_exists(subject_did, device_id),
         {:ok, normalized_pre_keys} <- normalize_pre_keys(pre_keys) do
      now = now()

      rows =
        Enum.map(normalized_pre_keys, fn pre_key ->
          %{
            subject_did: subject_did,
            device_id: device_id,
            pre_key_id: pre_key["pre_key_id"],
            pre_key: pre_key["pre_key"],
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(PreKey, rows,
        on_conflict: :nothing,
        conflict_target: [:subject_did, :device_id, :pre_key_id]
      )

      {:ok, normalized_pre_keys}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def reserve_bundle(subject_did) do
    Repo.transaction(fn ->
      devices =
        Device
        |> where([device], device.subject_did == ^subject_did)
        |> order_by([device], asc: device.device_id)
        |> Repo.all()

      Enum.map(devices, fn device ->
        pre_key = reserve_next_pre_key(device.subject_did, device.device_id)
        bundle_device(device_map(device), pre_key)
      end)
    end)
    |> case do
      {:ok, devices} -> {:ok, %{subject_did: subject_did, devices: devices}}
      {:error, reason} -> {:error, reason}
    end
  end

  def device_availability(subject_did) do
    devices =
      Device
      |> where([device], device.subject_did == ^subject_did)
      |> order_by([device], asc: device.device_id)
      |> Repo.all()
      |> Enum.map(fn device ->
        device
        |> device_map()
        |> Map.put("has_one_time_pre_keys", has_available_pre_keys?(device))
      end)

    {:ok, %{subject_did: subject_did, devices: devices}}
  end

  def store_message(attrs) do
    with :ok <- reject_plaintext_fields(attrs),
         {:ok, message_id} <- fetch_string(attrs, "message_id"),
         {:ok, sender_did} <- fetch_string(attrs, "sender_did"),
         {:ok, sender_device_id} <- fetch_string(attrs, "sender_device_id"),
         {:ok, recipient_did} <- fetch_string(attrs, "recipient_did"),
         {:ok, recipient_device_id} <- fetch_string(attrs, "recipient_device_id"),
         {:ok, ciphertext_type} <- fetch_string(attrs, "ciphertext_type"),
         {:ok, ciphertext} <- fetch_string(attrs, "ciphertext"),
         {:ok, protocol_version} <- fetch_string(attrs, "protocol_version"),
         :ok <- reject_duplicate_message(message_id) do
      now = now()

      message = %Message{
        message_id: message_id,
        sender_did: sender_did,
        sender_device_id: sender_device_id,
        recipient_did: recipient_did,
        recipient_device_id: recipient_device_id,
        ciphertext_type: ciphertext_type,
        ciphertext: ciphertext,
        protocol_version: protocol_version,
        message_created_at: Map.get(attrs, "created_at"),
        inserted_at: now,
        updated_at: now
      }

      {:ok, message} = Repo.insert(message)
      {:ok, message_map(message)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def mailbox(recipient_did, recipient_device_id) do
    acked_message_ids =
      Ack
      |> where([ack], ack.recipient_device_id == ^recipient_device_id)
      |> select([ack], ack.message_id)
      |> Repo.all()
      |> MapSet.new()

    messages =
      Message
      |> where(
        [message],
        message.recipient_did == ^recipient_did and
          message.recipient_device_id == ^recipient_device_id
      )
      |> order_by([message], asc: message.message_created_at, asc: message.inserted_at)
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(acked_message_ids, &1.message_id))
      |> Enum.map(&message_map/1)

    {:ok, messages}
  end

  def ack(message_id, recipient_did, recipient_device_id) do
    case Repo.get_by(Message, message_id: message_id) do
      nil ->
        {:error, :not_found}

      %Message{recipient_did: ^recipient_did, recipient_device_id: ^recipient_device_id} =
          message ->
        now = now()

        %Ack{
          message_id: message_id,
          recipient_device_id: recipient_device_id,
          acked_at: now,
          inserted_at: now,
          updated_at: now
        }
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: [:message_id, :recipient_device_id]
        )

        {:ok, message_map(message)}

      _message ->
        {:error, :recipient_mismatch}
    end
  end

  def reset do
    Repo.delete_all(Ack)
    Repo.delete_all(Message)
    Repo.delete_all(PreKey)
    Repo.delete_all(Device)
    :ok
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  defp reserve_next_pre_key(subject_did, device_id) do
    query =
      PreKey
      |> where(
        [pre_key],
        pre_key.subject_did == ^subject_did and pre_key.device_id == ^device_id and
          is_nil(pre_key.reserved_at)
      )
      |> order_by([pre_key], asc: pre_key.pre_key_id)
      |> limit(1)
      |> lock("FOR UPDATE SKIP LOCKED")

    case Repo.one(query) do
      nil ->
        nil

      pre_key ->
        {1, _} =
          PreKey
          |> where([candidate], candidate.id == ^pre_key.id)
          |> Repo.update_all(set: [reserved_at: now(), updated_at: now()])

        pre_key_map(pre_key)
    end
  end

  defp device_map(device) do
    %{
      "subject_did" => device.subject_did,
      "device_id" => device.device_id,
      "messenger_identity_key" => device.messenger_identity_key,
      "signed_pre_key_id" => device.signed_pre_key_id,
      "signed_pre_key" => device.signed_pre_key,
      "signed_pre_key_signature" => device.signed_pre_key_signature,
      "expires_at" => device.expires_at,
      "binding" => device.binding || %{},
      "binding_signature" => device.binding_signature
    }
  end

  defp pre_key_map(pre_key) do
    %{"pre_key_id" => pre_key.pre_key_id, "pre_key" => pre_key.pre_key}
  end

  defp message_map(message) do
    %{
      "message_id" => message.message_id,
      "sender_did" => message.sender_did,
      "sender_device_id" => message.sender_device_id,
      "recipient_did" => message.recipient_did,
      "recipient_device_id" => message.recipient_device_id,
      "ciphertext_type" => message.ciphertext_type,
      "ciphertext" => message.ciphertext,
      "protocol_version" => message.protocol_version,
      "created_at" => message.message_created_at
    }
  end

  defp bundle_device(device, nil), do: device

  defp bundle_device(device, pre_key) do
    device
    |> Map.put("one_time_pre_key_id", pre_key["pre_key_id"])
    |> Map.put("one_time_pre_key", pre_key["pre_key"])
  end

  defp has_available_pre_keys?(device) do
    Repo.exists?(
      from(pre_key in PreKey,
        where:
          pre_key.subject_did == ^device.subject_did and
            pre_key.device_id == ^device.device_id and
            is_nil(pre_key.reserved_at)
      )
    )
  end

  defp ensure_device_exists(subject_did, device_id) do
    if Repo.exists?(
         from(device in Device,
           where: device.subject_did == ^subject_did and device.device_id == ^device_id
         )
       ) do
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

  defp reject_duplicate_message(message_id) do
    if Repo.exists?(from(message in Message, where: message.message_id == ^message_id)) do
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

  defp now, do: DateTime.utc_now()
end
