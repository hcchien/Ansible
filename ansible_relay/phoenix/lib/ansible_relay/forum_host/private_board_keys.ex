defmodule AnsibleRelay.ForumHost.PrivateBoardKeys do
  @moduledoc "Host-blind storage for private-board device keys and wrapped epoch keys."

  import Ecto.Query

  alias AnsibleRelay.Db.{
    ForumHostBoard,
    ForumHostBoardDeviceKey,
    ForumHostBoardEncryptionEpoch,
    ForumHostBoardEpochEnvelope
  }

  alias AnsibleRelay.Repo

  @envelope_keys MapSet.new(~w(
    version board_id epoch recipient_device_key_id recipient_public_key_hash
    sender_public_key_hash policy_version algorithm sender_public_key_hex nonce
    ciphertext mac
  ))

  @content_envelope_keys MapSet.new(~w(
    version board_id epoch record_id record_type author_pairwise_id created_at
    policy_version algorithm nonce ciphertext mac
  ))

  def validate_content_envelope(%ForumHostBoard{} = board, entity_type, entity_id, payload)
      when entity_type in ["thread", "post"] and is_binary(entity_id) and is_map(payload) do
    envelope = payload["private_envelope"]
    plaintext_keys = ~w(title content body text)

    cond do
      board.content_visibility != "end_to_end_encrypted" ->
        if is_nil(envelope), do: :ok, else: {:error, :encrypted_content_not_allowed}

      board.encryption_state != "ready" ->
        {:error, :private_board_rotation_required}

      Enum.any?(plaintext_keys, &Map.has_key?(payload, &1)) ->
        {:error, :private_board_plaintext_forbidden}

      not valid_content_envelope?(board, entity_type, entity_id, envelope) ->
        {:error, :invalid_private_content_envelope}

      true ->
        :ok
    end
  end

  def validate_content_envelope(_board, _entity_type, _entity_id, _payload),
    do: {:error, :invalid_private_content_envelope}

  def register_device(board_id, grant, attrs) do
    with %ForumHostBoard{} = board <- Repo.get(ForumHostBoard, board_id),
         :ok <- encrypted_board_ready_for_key_ops(board, grant),
         {:ok, public_hex, public_hash} <- parse_public_key(attrs["agreement_public_key_hex"]) do
      key_attrs = %{
        hosted_board_id: board_id,
        device_key_id: public_hash,
        agreement_public_key_hex: public_hex,
        public_key_hash: public_hash,
        pairwise_subject_hash: grant.pairwise_subject_hash,
        device_signing_thumbprint: grant.device_key_thumbprint,
        policy_version: board.access_policy_version,
        state: "active"
      }

      Repo.transaction(fn ->
        {key, inserted?} =
          case Repo.get_by(ForumHostBoardDeviceKey,
                 hosted_board_id: board_id,
                 public_key_hash: public_hash
               ) do
            nil ->
              key =
                %ForumHostBoardDeviceKey{}
                |> ForumHostBoardDeviceKey.changeset(key_attrs)
                |> Repo.insert!()

              {key, true}

            existing ->
              if existing.pairwise_subject_hash != grant.pairwise_subject_hash or
                   existing.device_signing_thumbprint != grant.device_key_thumbprint or
                   existing.state != "active" do
                Repo.rollback(:device_key_conflict)
              end

              updated =
                if existing.policy_version != board.access_policy_version do
                  existing
                  |> Ecto.Changeset.change(policy_version: board.access_policy_version)
                  |> Repo.update!()
                else
                  existing
                end

              {updated, false}
          end

        if inserted? and board.encryption_epoch > 0 do
          board
          |> Ecto.Changeset.change(encryption_state: "rotation_required")
          |> Repo.update!()
        end

        key
      end)
    else
      nil -> {:error, :board_not_found}
      error -> error
    end
  end

  def list_active_devices(board_id, grant) do
    with %ForumHostBoard{} = board <- Repo.get(ForumHostBoard, board_id),
         :ok <- encrypted_board_ready_for_key_ops(board, grant) do
      devices =
        from(k in ForumHostBoardDeviceKey,
          where: k.hosted_board_id == ^board_id and k.state == "active",
          order_by: [asc: k.inserted_at],
          select: %{
            device_key_id: k.device_key_id,
            agreement_public_key_hex: k.agreement_public_key_hex,
            public_key_hash: k.public_key_hash,
            policy_version: k.policy_version
          }
        )
        |> Repo.all()

      {:ok, board, devices}
    else
      nil -> {:error, :board_not_found}
      error -> error
    end
  end

  def activate_epoch(_board_id, _grant, _epoch_number, _policy_version, []),
    do: {:error, :incomplete_epoch_envelopes}

  def activate_epoch(board_id, grant, epoch_number, policy_version, envelopes)
      when is_integer(epoch_number) and is_integer(policy_version) and is_list(envelopes) do
    Repo.transaction(fn ->
      board =
        from(b in ForumHostBoard, where: b.hosted_board_id == ^board_id, lock: "FOR UPDATE")
        |> Repo.one()

      with %ForumHostBoard{} <- board,
           :ok <- encrypted_board_ready_for_key_ops(board, grant),
           true <- policy_version == board.access_policy_version,
           true <- epoch_number == board.encryption_epoch + 1,
           active when active != [] <- active_devices(board_id),
           true <- sender_registered?(active, grant, envelopes),
           {:ok, normalized} <- validate_envelopes(board, epoch_number, active, envelopes) do
        epoch =
          %ForumHostBoardEncryptionEpoch{}
          |> ForumHostBoardEncryptionEpoch.changeset(%{
            hosted_board_id: board_id,
            epoch: epoch_number,
            policy_version: policy_version,
            state: "ready",
            created_by_subject_hash: grant.pairwise_subject_hash
          })
          |> Repo.insert!()

        Enum.each(normalized, fn {device, envelope} ->
          %ForumHostBoardEpochEnvelope{}
          |> ForumHostBoardEpochEnvelope.changeset(%{
            epoch_id: epoch.id,
            recipient_device_key_id: device.id,
            sender_public_key_hash: envelope["sender_public_key_hash"],
            envelope: envelope
          })
          |> Repo.insert!()
        end)

        from(e in ForumHostBoardEncryptionEpoch,
          where: e.hosted_board_id == ^board_id and e.id != ^epoch.id and e.state == "ready"
        )
        |> Repo.update_all(set: [state: "superseded"])

        board
        |> Ecto.Changeset.change(
          encryption_epoch: epoch_number,
          encryption_state: "ready"
        )
        |> Repo.update!()

        epoch
      else
        nil -> Repo.rollback(:board_not_found)
        false -> Repo.rollback(:invalid_encryption_epoch)
        [] -> Repo.rollback(:no_active_devices)
        {:error, reason} -> Repo.rollback(reason)
        _ -> Repo.rollback(:invalid_encryption_epoch)
      end
    end)
  end

  def current_envelope(board_id, grant) do
    with %ForumHostBoard{content_visibility: "end_to_end_encrypted", encryption_state: "ready"} =
           board <- Repo.get(ForumHostBoard, board_id),
         true <- grant.policy_version == board.access_policy_version,
         %ForumHostBoardDeviceKey{} = key <-
           Repo.one(
             from(k in ForumHostBoardDeviceKey,
               where:
                 k.hosted_board_id == ^board_id and k.state == "active" and
                   k.pairwise_subject_hash == ^grant.pairwise_subject_hash and
                   k.device_signing_thumbprint == ^grant.device_key_thumbprint,
               order_by: [desc: k.inserted_at],
               limit: 1
             )
           ),
         %ForumHostBoardEpochEnvelope{} = envelope <-
           Repo.one(
             from(w in ForumHostBoardEpochEnvelope,
               join: e in ForumHostBoardEncryptionEpoch,
               on: e.id == w.epoch_id,
               where:
                 e.hosted_board_id == ^board_id and e.epoch == ^board.encryption_epoch and
                   e.state == "ready" and w.recipient_device_key_id == ^key.id,
               limit: 1
             )
           ) do
      {:ok, board, envelope.envelope}
    else
      nil -> {:error, :epoch_key_unavailable}
      false -> {:error, :stale_policy}
      _ -> {:error, :private_board_not_ready}
    end
  end

  def revoke_device(board_id, grant, device_key_id) do
    Repo.transaction(fn ->
      board =
        from(b in ForumHostBoard, where: b.hosted_board_id == ^board_id, lock: "FOR UPDATE")
        |> Repo.one()

      with %ForumHostBoard{} <- board,
           :ok <- encrypted_board_ready_for_key_ops(board, grant),
           %ForumHostBoardDeviceKey{} = key <-
             Repo.get_by(ForumHostBoardDeviceKey,
               hosted_board_id: board_id,
               device_key_id: device_key_id,
               state: "active"
             ) do
        key
        |> Ecto.Changeset.change(state: "revoked", revoked_at: DateTime.utc_now())
        |> Repo.update!()

        board
        |> Ecto.Changeset.change(encryption_state: "rotation_required")
        |> Repo.update!()

        key
      else
        nil -> Repo.rollback(:device_key_not_found)
        {:error, reason} -> Repo.rollback(reason)
        _ -> Repo.rollback(:private_board_not_ready)
      end
    end)
  end

  defp encrypted_board_ready_for_key_ops(board, grant) do
    cond do
      board.content_visibility != "end_to_end_encrypted" ->
        {:error, :not_encrypted_board}

      not Application.get_env(:ansible_relay, :encrypted_boards_enabled, false) ->
        {:error, :encrypted_boards_not_enabled}

      grant.hosted_board_id != board.hosted_board_id ->
        {:error, :invalid_board_capability}

      grant.policy_version != board.access_policy_version ->
        {:error, :stale_policy}

      true ->
        :ok
    end
  end

  defp active_devices(board_id) do
    from(k in ForumHostBoardDeviceKey,
      where: k.hosted_board_id == ^board_id and k.state == "active"
    )
    |> Repo.all()
  end

  defp sender_registered?(active, grant, envelopes) do
    sender_hashes = envelopes |> Enum.map(& &1["sender_public_key_hash"]) |> Enum.uniq()

    length(sender_hashes) == 1 and
      Enum.any?(active, fn key ->
        key.public_key_hash == hd(sender_hashes) and
          key.pairwise_subject_hash == grant.pairwise_subject_hash and
          key.device_signing_thumbprint == grant.device_key_thumbprint
      end)
  end

  defp validate_envelopes(board, epoch, active, envelopes) do
    by_id = Map.new(active, &{&1.device_key_id, &1})

    normalized =
      Enum.reduce_while(envelopes, {:ok, []}, fn envelope, {:ok, result} ->
        device = by_id[envelope["recipient_device_key_id"]]

        if valid_envelope?(board, epoch, device, envelope) do
          {:cont, {:ok, [{device, envelope} | result]}}
        else
          {:halt, {:error, :invalid_epoch_envelope}}
        end
      end)

    with {:ok, entries} <- normalized,
         ids <- Enum.map(entries, fn {device, _} -> device.device_key_id end),
         true <- length(ids) == map_size(by_id) and MapSet.new(ids) == MapSet.new(Map.keys(by_id)) do
      {:ok, entries}
    else
      false -> {:error, :incomplete_epoch_envelopes}
      error -> error
    end
  end

  defp valid_envelope?(board, epoch, %ForumHostBoardDeviceKey{} = device, envelope)
       when is_map(envelope) do
    MapSet.new(Map.keys(envelope)) == @envelope_keys and
      envelope["version"] == 1 and
      envelope["algorithm"] == "P256-HKDF-SHA256+A256GCM" and
      envelope["board_id"] == board.hosted_board_id and
      envelope["epoch"] == epoch and
      envelope["policy_version"] == board.access_policy_version and
      envelope["recipient_device_key_id"] == device.device_key_id and
      envelope["recipient_public_key_hash"] == device.public_key_hash and
      valid_hex_key?(envelope["sender_public_key_hex"]) and
      hash_public(envelope["sender_public_key_hex"]) == envelope["sender_public_key_hash"] and
      encoded_length?(envelope["nonce"], 12) and encoded_length?(envelope["mac"], 16) and
      encoded_length?(envelope["ciphertext"], 32)
  end

  defp valid_envelope?(_, _, _, _), do: false

  defp valid_content_envelope?(board, entity_type, entity_id, envelope)
       when is_map(envelope) do
    with true <- MapSet.new(Map.keys(envelope)) == @content_envelope_keys,
         true <- envelope["version"] == 1,
         true <- envelope["algorithm"] == "A256GCM",
         true <- envelope["board_id"] == board.hosted_board_id,
         true <- envelope["epoch"] == board.encryption_epoch,
         true <- envelope["policy_version"] == board.access_policy_version,
         true <- envelope["record_id"] == entity_id,
         true <- envelope["record_type"] == entity_type,
         true <- non_empty?(envelope["author_pairwise_id"], 512),
         {:ok, _created_at, 0} <- DateTime.from_iso8601(envelope["created_at"]),
         true <- encoded_length?(envelope["nonce"], 12),
         true <- encoded_length?(envelope["mac"], 16),
         {:ok, ciphertext} <- Base.url_decode64(envelope["ciphertext"], padding: false),
         true <- byte_size(ciphertext) in 1..1_048_576 do
      true
    else
      _ -> false
    end
  end

  defp valid_content_envelope?(_, _, _, _), do: false

  defp non_empty?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max

  defp parse_public_key(value) do
    if valid_hex_key?(value) do
      normalized = String.downcase(value)
      {:ok, normalized, hash_public(normalized)}
    else
      {:error, :invalid_device_agreement_key}
    end
  end

  defp valid_hex_key?("04" <> rest) when byte_size(rest) == 128,
    do: String.match?(rest, ~r/\A[0-9a-fA-F]+\z/)

  defp valid_hex_key?(_), do: false

  defp hash_public(value) do
    value
    |> Base.decode16!(case: :mixed)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp encoded_length?(value, length) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} -> byte_size(decoded) == length
      :error -> false
    end
  end

  defp encoded_length?(_, _), do: false
end
