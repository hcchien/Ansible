defmodule AnsibleRelay.CommunityNotes.ContextNote do
  @moduledoc """
  Validates public, revision-pinned Community Note operations.

  A context note is a signed public content object, but it is not a reply and
  never changes the distribution or moderation state of its target. Ratings
  travel on the private Forum Host intent rail instead of the public op log.
  """

  alias AnsibleRelay.{OpStore}
  alias AnsibleRelay.ForumHost.PostingGate

  @target_types ~w(murmur note thread post)
  @max_body 1_000
  @max_sources 5
  @max_source_title 200
  @hash_pattern ~r/^sha256:[0-9a-f]{64}$/

  @spec validate_op(map()) :: :ok | {:error, atom()}
  def validate_op(%{"entity_type" => type}) when type != "context_note", do: :ok

  def validate_op(%{"entity_type" => "context_note", "op_type" => "delete"}), do: :ok

  def validate_op(%{"entity_type" => "context_note", "op_type" => op_type} = params)
      when op_type in ["insert", "update"] do
    with {:ok, payload} <- decode_payload(params["payload"]),
         :ok <- validate_payload(payload),
         :ok <- validate_retarget(params, payload),
         {:ok, target} <- target_op(payload),
         :ok <- validate_target_hash(target, payload),
         :ok <- validate_target_public(target, payload) do
      :ok
    end
  end

  def validate_op(%{"entity_type" => "context_note"}),
    do: {:error, :invalid_context_note_payload}

  def validate_op(_params), do: :ok

  defp validate_payload(payload) do
    with type when type in @target_types <- payload["targetEntityType"],
         id when is_binary(id) and id != "" <- payload["targetEntityId"],
         op_id when is_binary(op_id) and op_id != "" <- payload["targetOpId"],
         hash when is_binary(hash) <- payload["targetContentHash"],
         true <- Regex.match?(@hash_pattern, hash),
         body when is_binary(body) <- payload["body"],
         true <- String.length(String.trim(body)) in 1..@max_body,
         sources when is_list(sources) <- payload["sources"],
         true <- length(sources) in 1..@max_sources,
         true <- Enum.all?(sources, &valid_source?/1),
         "public" <- payload["visibility"] do
      :ok
    else
      _ -> {:error, :invalid_context_note_payload}
    end
  end

  defp valid_source?(%{"url" => url} = source) when is_binary(url) do
    uri = URI.parse(url)
    title = Map.get(source, "title")

    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
      (is_nil(title) or (is_binary(title) and String.length(title) <= @max_source_title))
  end

  defp valid_source?(_source), do: false

  defp target_op(payload) do
    expected_type = payload["targetEntityType"]
    expected_id = payload["targetEntityId"]

    case OpStore.get_by_op_id(payload["targetOpId"]) do
      nil ->
        {:error, :context_note_target_not_found}

      %{entity_type: ^expected_type, entity_id: ^expected_id, op_type: op_type} = target
      when op_type != "delete" ->
        {:ok, target}

      _ ->
        {:error, :context_note_target_mismatch}
    end
  end

  defp validate_target_public(target, note_payload) do
    payload = decode_target_payload(target.payload)
    target_board = payload["boardId"] || payload["board_id"]
    note_board = note_payload["boardId"] || note_payload["board_id"]

    cond do
      not is_nil(target_board) and target_board != note_board ->
        {:error, :context_note_target_mismatch}

      target.entity_type in ["murmur", "note"] ->
        if payload["visibility"] in [nil, "public"],
          do: :ok,
          else: {:error, :context_note_target_not_public}

      target.entity_type in ["thread", "post"] ->
        public_board?(target_board)

      true ->
        {:error, :context_note_target_not_public}
    end
  end

  defp validate_target_hash(target, note_payload) do
    actual =
      target.payload
      |> decode_target_payload()
      |> canonical_json()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> then(&("sha256:" <> &1))

    if actual == note_payload["targetContentHash"],
      do: :ok,
      else: {:error, :context_note_target_mismatch}
  end

  defp public_board?(board_id) when is_binary(board_id) do
    case PostingGate.get_board(board_id) do
      %{
        content_visibility: "public",
        access_policy: %{"read" => %{"requirement" => "public"}}
      } ->
        :ok

      _ ->
        {:error, :context_note_target_not_public}
    end
  end

  defp public_board?(_board_id), do: {:error, :context_note_target_not_public}

  defp validate_retarget(%{"op_type" => "insert"}, _payload), do: :ok

  defp validate_retarget(%{"op_type" => "update", "entity_id" => note_id}, payload) do
    case OpStore.create_op("context_note", note_id) do
      nil ->
        {:error, :context_note_target_not_found}

      create ->
        original = decode_target_payload(create.payload)

        if target_tuple(original) == target_tuple(payload),
          do: :ok,
          else: {:error, :context_note_retarget_forbidden}
    end
  end

  defp validate_retarget(_params, _payload), do: {:error, :invalid_context_note_payload}

  defp target_tuple(payload) do
    {
      payload["targetEntityType"],
      payload["targetEntityId"],
      payload["targetOpId"],
      payload["targetContentHash"],
      payload["boardId"] || payload["board_id"]
    }
  end

  defp decode_payload(payload) when is_map(payload), do: {:ok, payload}

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = value} ->
        {:ok, value}

      _ ->
        with {:ok, decoded} <- Base.decode64(payload),
             {:ok, %{} = value} <- Jason.decode(decoded) do
          {:ok, value}
        else
          _ -> {:error, :invalid_context_note_payload}
        end
    end
  end

  defp decode_payload(_payload), do: {:error, :invalid_context_note_payload}

  defp decode_target_payload(payload) when is_map(payload), do: payload

  defp decode_target_payload(payload) when is_binary(payload) do
    case decode_payload(payload) do
      {:ok, value} -> value
      _ -> %{}
    end
  end

  defp decode_target_payload(_payload), do: %{}

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

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)
end
