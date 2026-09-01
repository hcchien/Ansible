defmodule AnsibleRelay.MessengerStore do
  @moduledoc """
  Ecto-backed encrypted messenger relay store.

  The relay stores public device bundles, one-time pre-keys, and opaque
  ciphertext messages. It never accepts plaintext message fields.
  """

  use GenServer
  import Ecto.Query

  alias AnsibleRelay.{MessengerPolicy, Repo}

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
      field(:revoked_at, :utc_datetime_usec)
      field(:revocation_reason, :string)

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
      field(:reserved_by_did, :string)
      field(:reserved_by_device_id, :string)
      field(:reservation_request_id, :string)

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
      field(:expires_at, :utc_datetime_usec)

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
         :ok <- MessengerPolicy.validate_device(subject_did, device_id, bundle),
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
         :ok <- MessengerPolicy.validate_database_strings([subject_did, device_id]),
         :ok <- MessengerPolicy.validate_pre_keys(pre_keys),
         :ok <- ensure_active_device(subject_did, device_id),
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

  def revoke_device(subject_did, device_id, reason) do
    now = now()

    case Repo.get_by(Device, subject_did: subject_did, device_id: device_id) do
      nil ->
        {:error, :device_not_found}

      %Device{} = device ->
        revoked_at = device.revoked_at || now

        {1, _} =
          Device
          |> where([candidate], candidate.id == ^device.id)
          |> Repo.update_all(
            set: [revoked_at: revoked_at, revocation_reason: reason, updated_at: now]
          )

        PreKey
        |> where(
          [pre_key],
          pre_key.subject_did == ^subject_did and pre_key.device_id == ^device_id
        )
        |> Repo.delete_all()

        {:ok, Map.put(device_map(device), "revoked_at", revoked_at)}
    end
  end

  def reserve_bundle(subject_did, requester_did, requester_device_id, request_id) do
    with :ok <- ensure_active_device(requester_did, requester_device_id) do
      Repo.transaction(fn ->
        devices =
          Device
          |> where([device], device.subject_did == ^subject_did)
          |> where([device], is_nil(device.revoked_at))
          |> order_by([device], asc: device.device_id)
          |> lock("FOR UPDATE")
          |> Repo.all()
          |> Enum.filter(&device_active?/1)

        Enum.map(devices, fn device ->
          pre_key =
            reserve_next_pre_key(
              device.subject_did,
              device.device_id,
              requester_did,
              requester_device_id,
              request_id
            )

          bundle_device(device_map(device), pre_key)
        end)
      end)
      |> case do
        {:ok, devices} -> {:ok, %{subject_did: subject_did, devices: devices}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def device_availability(subject_did) do
    devices =
      Device
      |> where([device], device.subject_did == ^subject_did)
      |> where([device], is_nil(device.revoked_at))
      |> order_by([device], asc: device.device_id)
      |> Repo.all()
      |> Enum.filter(&device_active?/1)
      |> Enum.map(fn device ->
        device
        |> device_map()
        |> Map.put("has_one_time_pre_keys", has_available_pre_keys?(device))
      end)

    {:ok, %{subject_did: subject_did, devices: devices}}
  end

  def store_message(attrs) do
    case insert_message(attrs) do
      {:ok, message, inserted?} ->
        if inserted? do
          AnsibleRelay.Push.WakeScheduler.mailbox_delivered(
            message["sender_did"],
            message["recipient_did"]
          )
        end

        {:ok, message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def store_messages(messages) when is_list(messages) and messages != [] do
    with :ok <- MessengerPolicy.validate_messages(messages) do
      Repo.transaction(fn ->
        Enum.map(messages, fn attrs ->
          case insert_message(attrs) do
            {:ok, message, inserted?} -> {message, inserted?}
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
      end)
      |> case do
        {:ok, results} ->
          results
          |> Enum.filter(fn {_message, inserted?} -> inserted? end)
          |> Enum.map(fn {message, _inserted?} ->
            {message["sender_did"], message["recipient_did"]}
          end)
          |> Enum.uniq()
          |> Enum.each(fn {sender_did, recipient_did} ->
            AnsibleRelay.Push.WakeScheduler.mailbox_delivered(sender_did, recipient_did)
          end)

          {:ok, Enum.map(results, fn {message, _inserted?} -> message end)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def store_messages(_messages), do: {:error, :messages_required}

  defp insert_message(attrs) do
    with :ok <- MessengerPolicy.validate_message(attrs),
         :ok <- reject_plaintext_fields(attrs),
         {:ok, message_id} <- fetch_string(attrs, "message_id"),
         {:ok, sender_did} <- fetch_string(attrs, "sender_did"),
         {:ok, sender_device_id} <- fetch_string(attrs, "sender_device_id"),
         {:ok, recipient_did} <- fetch_string(attrs, "recipient_did"),
         {:ok, recipient_device_id} <- fetch_string(attrs, "recipient_device_id"),
         {:ok, ciphertext_type} <- fetch_string(attrs, "ciphertext_type"),
         {:ok, ciphertext} <- fetch_string(attrs, "ciphertext"),
         {:ok, protocol_version} <- fetch_string(attrs, "protocol_version"),
         :ok <- ensure_active_device(sender_did, sender_device_id),
         :ok <- ensure_active_device(recipient_did, recipient_device_id) do
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
        expires_at: DateTime.add(now, ciphertext_retention_days() * 86_400, :second),
        inserted_at: now,
        updated_at: now
      }

      case Repo.insert(message,
             on_conflict: :nothing,
             conflict_target: [:message_id],
             returning: true
           ) do
        {:ok, %Message{id: nil}} ->
          existing = Repo.get_by!(Message, message_id: message_id)

          if same_message?(existing, message) do
            {:ok, message_map(existing), false}
          else
            {:error, :message_id_conflict}
          end

        {:ok, %Message{} = inserted} ->
          {:ok, message_map(inserted), true}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def mailbox(recipient_did, recipient_device_id, cursor \\ nil, limit \\ 100) do
    with :ok <- ensure_active_device(recipient_did, recipient_device_id),
         {:ok, cursor_id} <- decode_cursor(cursor) do
      purge_expired_messages()

      fetched_rows =
        Message
        |> join(:left, [message], ack in Ack,
          on:
            ack.message_id == message.message_id and
              ack.recipient_device_id == ^recipient_device_id
        )
        |> where(
          [message, ack],
          message.recipient_did == ^recipient_did and
            message.recipient_device_id == ^recipient_device_id and
            is_nil(ack.id)
        )
        |> where([message, _ack], message.id > ^cursor_id)
        |> order_by([message, _ack], asc: message.id)
        |> limit(^limit)
        |> Repo.all()

      next_cursor =
        case List.last(fetched_rows) do
          nil -> cursor
          row -> encode_cursor(row.id)
        end

      {:ok, %{messages: Enum.map(fetched_rows, &message_map/1), next_cursor: next_cursor}}
    end
  end

  def ack(message_id, recipient_did, recipient_device_id) do
    with :ok <- ensure_active_device(recipient_did, recipient_device_id) do
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
  end

  def purge_expired_messages(limit \\ 1_000) when is_integer(limit) and limit > 0 do
    Repo.transaction(fn ->
      expired_ids =
        Message
        |> where([message], message.expires_at <= ^now())
        |> order_by([message], asc: message.id)
        |> limit(^limit)
        |> lock("FOR UPDATE SKIP LOCKED")
        |> select([message], message.message_id)
        |> Repo.all()

      Ack
      |> where([ack], ack.message_id in ^expired_ids)
      |> Repo.delete_all()

      {count, _} =
        Message
        |> where([message], message.message_id in ^expired_ids)
        |> Repo.delete_all()

      count
    end)
    |> case do
      {:ok, count} -> count
      {:error, _reason} -> 0
    end
  end

  def metrics_snapshot do
    message_count = Repo.aggregate(Message, :count, :id)

    available_pre_keys =
      PreKey
      |> where([pre_key], is_nil(pre_key.reserved_at))
      |> Repo.aggregate(:count, :id)

    oldest_inserted_at =
      Message
      |> select([message], min(message.inserted_at))
      |> Repo.one()

    oldest_age_seconds =
      case oldest_inserted_at do
        nil -> 0
        inserted_at -> max(DateTime.diff(now(), inserted_at, :second), 0)
      end

    %{
      message_count: message_count,
      available_pre_keys: available_pre_keys,
      oldest_ciphertext_age_seconds: oldest_age_seconds
    }
  rescue
    _ -> %{message_count: 0, available_pre_keys: 0, oldest_ciphertext_age_seconds: 0}
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

  defp reserve_next_pre_key(
         subject_did,
         device_id,
         requester_did,
         requester_device_id,
         request_id
       ) do
    existing =
      Repo.one(
        from(pre_key in PreKey,
          where:
            pre_key.subject_did == ^subject_did and pre_key.device_id == ^device_id and
              pre_key.reserved_by_did == ^requester_did and
              pre_key.reserved_by_device_id == ^requester_device_id and
              pre_key.reservation_request_id == ^request_id,
          limit: 1
        )
      )

    case existing do
      %PreKey{} = pre_key ->
        pre_key_map(pre_key)

      nil ->
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
            timestamp = now()

            {1, _} =
              PreKey
              |> where([candidate], candidate.id == ^pre_key.id)
              |> Repo.update_all(
                set: [
                  reserved_at: timestamp,
                  reserved_by_did: requester_did,
                  reserved_by_device_id: requester_device_id,
                  reservation_request_id: request_id,
                  updated_at: timestamp
                ]
              )

            pre_key_map(pre_key)
        end
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

  defp ensure_active_device(subject_did, device_id) do
    case Repo.one(
           from(device in Device,
             where:
               device.subject_did == ^subject_did and device.device_id == ^device_id and
                 is_nil(device.revoked_at),
             limit: 1
           )
         ) do
      %Device{} = device -> if device_active?(device), do: :ok, else: {:error, :device_not_active}
      nil -> {:error, :device_not_active}
    end
  end

  defp device_active?(%Device{revoked_at: revoked_at}) when not is_nil(revoked_at), do: false
  defp device_active?(%Device{expires_at: nil}), do: true
  defp device_active?(%Device{expires_at: ""}), do: true

  defp device_active?(%Device{expires_at: expires_at}) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, expiry, _offset} -> DateTime.compare(expiry, now()) == :gt
      _ -> false
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

  defp same_message?(left, right) do
    Enum.all?(
      ~w(message_id sender_did sender_device_id recipient_did recipient_device_id ciphertext_type ciphertext protocol_version message_created_at)a,
      &(Map.get(left, &1) == Map.get(right, &1))
    )
  end

  defp decode_cursor(nil), do: {:ok, 0}
  defp decode_cursor(""), do: {:ok, 0}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         {value, ""} <- Integer.parse(raw),
         true <- value >= 0 do
      {:ok, value}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp encode_cursor(id), do: id |> Integer.to_string() |> Base.url_encode64(padding: false)

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

  defp ciphertext_retention_days do
    Application.get_env(:ansible_relay, :messenger_ciphertext_retention_days, 30)
  end
end
