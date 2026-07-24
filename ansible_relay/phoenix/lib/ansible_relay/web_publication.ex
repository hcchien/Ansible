defmodule AnsibleRelay.WebPublication do
  @moduledoc """
  Content-bound WebAuthn publication operations shared by the Forum Host,
  Relay sync log, AppView, and federation delivery.
  """

  alias AnsibleRelay.{OpStore, PublicationIntentStore, Repo, WebauthnSync}
  alias AnsibleRelay.Db.WebPublicationOperation
  alias AnsibleRelay.ForumHost.{PostingGate, ReceiptSigner, Store}

  @actions %{
    "forum.publish" => {"forum:post", "thread", "insert"},
    "forum.reply" => {"forum:reply", "post", "insert"},
    "forum.edit" => {"forum:edit", nil, "update"},
    "forum.delete" => {"forum:delete", nil, "delete"},
    "forum.react" => {"forum:react", "reaction", "insert"},
    "forum.moderate" => {"forum:moderate", nil, "insert"}
  }
  @visibilities ~w(public unlisted)
  @max_operation_lifetime_seconds 300

  def prepare(session, session_id, operation, claimed_hash) do
    with {:ok, normalized, operation_hash, board} <-
           validate_operation(session, operation, claimed_hash),
         {:ok, options} <-
           WebauthnSync.publication_options(
             session.subject_did,
             session_id,
             normalized,
             operation_hash
           ) do
      {:ok, options, board}
    end
  end

  def accept(session, session_id, challenge_id, operation, claimed_hash, credential) do
    with {:ok, normalized, operation_hash, board} <-
           validate_operation(session, operation, claimed_hash) do
      case Repo.get(WebPublicationOperation, normalized["operation_id"]) do
        %WebPublicationOperation{operation_hash: ^operation_hash} = existing ->
          {:ok, existing, board}

        %WebPublicationOperation{} ->
          {:error, :operation_id_conflict}

        nil ->
          with {:ok, proof} <-
                 WebauthnSync.verify_publication(
                   session.subject_did,
                   session_id,
                   challenge_id,
                   normalized,
                   operation_hash,
                   credential
                 ),
               {:ok, accepted} <- persist(normalized, operation_hash, proof) do
            {:ok, accepted, board}
          end
      end
    end
  end

  def get_for_subject(operation_id, subject_did) do
    case Repo.get(WebPublicationOperation, operation_id) do
      %WebPublicationOperation{author_did: ^subject_did} = row -> {:ok, row}
      _ -> {:error, :not_found}
    end
  end

  def required_scope(action) do
    case @actions[action] do
      {scope, _entity_type, _op_type} -> {:ok, scope}
      nil -> {:error, :invalid_operation}
    end
  end

  def validate_operation(session, operation, claimed_hash)
      when is_map(operation) and is_binary(claimed_hash) do
    with :ok <- require(operation["type"] == "io.trisaura.webPublicationOperation"),
         :ok <- require(operation["version"] == 1),
         :ok <- nonempty(operation, ~w(operation_id author_did action target_forum_host board_id entity_type entity_id payload_hash created_at expires_at nonce)),
         :ok <- require(is_map(operation["payload"])),
         {:ok, scope} <- required_scope(operation["action"]),
         :ok <- require(scope in session.scopes, :missing_required_scope),
         :ok <- require(operation["author_did"] == session.subject_did, :session_subject_mismatch),
         :ok <- require(same_origin?(operation["target_forum_host"], Store.base_url()), :audience_mismatch),
         :ok <- require(operation["visibility"] in @visibilities, :visibility_not_allowed),
         :ok <- require(is_boolean(operation["federate"])),
         :ok <- validate_action_shape(operation),
         :ok <- validate_times(operation),
         payload_hash <- sha256(canonical_json(operation["payload"])),
         :ok <- require(String.downcase(operation["payload_hash"]) == payload_hash, :payload_hash_mismatch),
         operation_hash <- sha256(canonical_json(operation)),
         :ok <- require(String.downcase(claimed_hash) == operation_hash, :operation_hash_mismatch),
         board when not is_nil(board) <- PostingGate.get_board(operation["board_id"]),
         :ok <- validate_policy_version(operation, board) do
      {:ok, operation, operation_hash, board}
    else
      nil -> {:error, :board_not_found}
      {:error, _} = error -> error
      _ -> {:error, :invalid_operation}
    end
  end

  def validate_operation(_session, _operation, _claimed_hash),
    do: {:error, :invalid_operation}

  def canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  def canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  def canonical_json(value), do: Jason.encode!(value)

  def serialize(row) do
    %{
      operation_id: row.operation_id,
      operation_hash: row.operation_hash,
      author_did: row.author_did,
      action: row.action,
      target_forum_host: row.target_forum_host,
      board_id: row.board_id,
      entity_type: row.entity_type,
      entity_id: row.entity_id,
      operation: row.operation,
      author_proof: row.author_proof,
      host_receipt: row.host_receipt,
      status: row.status,
      accepted_at: DateTime.to_iso8601(row.accepted_at)
    }
  end

  defp persist(operation, operation_hash, proof) do
    case Repo.get(WebPublicationOperation, operation["operation_id"]) do
      %WebPublicationOperation{operation_hash: ^operation_hash} = existing ->
        {:ok, existing}

      %WebPublicationOperation{} ->
        {:error, :operation_id_conflict}

      nil ->
        Repo.transaction(fn ->
          with {:ok, receipt} <- ReceiptSigner.sign(operation_hash),
               {:ok, row} <- insert_operation(operation, operation_hash, proof, receipt),
               {:ok, _log_id} <- append_sync_op(operation, operation_hash, proof, receipt),
               :ok <- enqueue_federation(operation, proof) do
            row
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, row} -> {:ok, row}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp insert_operation(operation, operation_hash, proof, receipt) do
    now = DateTime.utc_now()

    %WebPublicationOperation{}
    |> WebPublicationOperation.changeset(%{
      operation_id: operation["operation_id"],
      operation_hash: operation_hash,
      author_did: operation["author_did"],
      action: operation["action"],
      target_forum_host: operation["target_forum_host"],
      board_id: operation["board_id"],
      entity_type: operation["entity_type"],
      entity_id: operation["entity_id"],
      operation: operation,
      author_proof: proof,
      host_receipt: receipt,
      status: "accepted",
      accepted_at: now
    })
    |> Repo.insert()
  end

  defp append_sync_op(operation, operation_hash, proof, receipt) do
    {_scope, _default_entity_type, op_type} = @actions[operation["action"]]

    payload =
      operation["payload"]
      |> Map.put("boardId", operation["board_id"])
      |> Map.put("threadId", operation["parent_id"])
      |> Map.put("createdAt", operation["created_at"])
      |> Map.put("publishedAt", operation["created_at"])
      |> Map.put("visibility", operation["visibility"])
      |> Map.put("federate", operation["federate"])
      |> Map.put("web_author_proof", proof)
      |> Map.put("web_operation_hash", operation_hash)
      |> Map.put("web_operation", operation)
      |> Map.put("web_host_receipt", receipt)
      |> Jason.encode!()

    OpStore.append(%{
      op_id: operation["operation_id"],
      author_did: operation["author_did"],
      entity_type: operation["entity_type"],
      entity_id: operation["entity_id"],
      op_type: op_type,
      payload: payload,
      signature: proof["signature"],
      schema_version: 1,
      received_at: DateTime.utc_now()
    })
  end

  defp enqueue_federation(%{"federate" => false}, _proof), do: :ok

  defp enqueue_federation(operation, proof) do
    action =
      case operation["action"] do
        value when value in ["forum.publish", "forum.reply"] -> "publish"
        "forum.edit" -> "update"
        "forum.delete" -> "delete"
        _ -> nil
      end

    if is_nil(action) do
      :ok
    else
      payload =
        operation["payload"]
        |> Map.put("board_id", operation["board_id"])
        |> Map.put("forum_host", operation["target_forum_host"])
        |> Map.put("web_operation_id", operation["operation_id"])
        |> Map.put("web_author_proof_scheme", proof["scheme"])

      case PublicationIntentStore.accept(%{
             intent_id: "webpub_#{operation["operation_id"]}",
             author_did: operation["author_did"],
             content_item_id: operation["entity_id"],
             action: action,
             visibility: operation["visibility"],
             payload: payload,
             payload_hash: operation["payload_hash"],
             signature: proof["signature"],
             signature_scheme: "webauthn-p256-sha256"
           }) do
        {:ok, _intent} -> :ok
        {:error, :duplicate} -> :ok
        {:error, _changeset} -> {:error, :federation_enqueue_failed}
      end
    end
  end

  defp validate_action_shape(operation) do
    with {_scope, required_entity_type, _op_type} <-
           @actions[operation["action"]] || {:error, :invalid_operation},
         :ok <-
           require(
             is_nil(required_entity_type) or operation["entity_type"] == required_entity_type
           ),
         :ok <- validate_action_binding(operation) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_operation}
    end
  end

  defp validate_action_binding(%{"action" => "forum.reply"} = operation),
    do: require(is_binary(operation["parent_id"]) and operation["parent_id"] != "")

  defp validate_action_binding(%{"action" => action} = operation)
       when action in ["forum.edit", "forum.delete"],
       do:
         require(
           is_binary(operation["expected_previous_revision"]) and
             operation["expected_previous_revision"] != ""
         )

  defp validate_action_binding(%{"action" => "forum.react"} = operation),
    do: require(is_binary(operation["parent_id"]) and operation["parent_id"] != "")

  defp validate_action_binding(_operation), do: :ok

  defp validate_times(operation) do
    with {:ok, created_at, _} <- DateTime.from_iso8601(operation["created_at"]),
         {:ok, expires_at, _} <- DateTime.from_iso8601(operation["expires_at"]),
         true <- DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
         lifetime <- DateTime.diff(expires_at, created_at, :second),
         true <- lifetime in 1..@max_operation_lifetime_seconds do
      :ok
    else
      _ -> {:error, :operation_expired}
    end
  end

  defp validate_policy_version(operation, board) do
    require(operation["board_policy_version"] == board.access_policy_version, :board_policy_version_conflict)
  end

  defp nonempty(map, keys) do
    require(
      Enum.all?(keys, fn key ->
        value = map[key]
        not is_nil(value) and value != ""
      end)
    )
  end

  defp same_origin?(left, right) do
    with %URI{scheme: ls, host: lh, port: lp} <- URI.parse(left),
         %URI{scheme: rs, host: rh, port: rp} <- URI.parse(right) do
      ls == rs and String.downcase(lh || "") == String.downcase(rh || "") and lp == rp
    else
      _ -> false
    end
  end

  defp sha256(value),
    do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp require(value, reason \\ :invalid_operation)
  defp require(true, _reason), do: :ok
  defp require(false, reason), do: {:error, reason}
end
