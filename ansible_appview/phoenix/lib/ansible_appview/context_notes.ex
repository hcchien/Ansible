defmodule AnsibleAppview.ContextNotes do
  @moduledoc """
  Public, signature-verified Community Note projection.

  This projection stores note content and provenance only. Individual usefulness
  ratings are private Forum Host inputs and are intentionally absent here.
  """

  import Ecto.Query

  alias AnsibleAppview.Db.{ContextNote, FeedItem}
  alias AnsibleAppview.Repo

  @target_types ~w(murmur note thread post)
  @hash_pattern ~r/^sha256:[0-9a-f]{64}$/

  defp read_repo, do: Application.get_env(:ansible_appview, :read_repo, Repo)

  def fold(op, payload, anchor_expires_at, pending_target_revisions \\ %{}) do
    case op["op_type"] do
      "delete" ->
        mark_deleted(op)

      type when type in ["insert", "update"] ->
        upsert(op, payload, anchor_expires_at, pending_target_revisions)

      _ ->
        :noop
    end
  end

  def for_target(target_ref, limit \\ 20) when is_binary(target_ref) do
    limit = limit |> min(100) |> max(1)

    read_repo().all(
      from(n in ContextNote,
        where: n.target_entity_id == ^target_ref and n.deleted == false,
        order_by: [desc: n.updated_log_id],
        limit: ^limit
      )
    )
    |> Enum.map(&to_map/1)
  end

  def get(note_id) when is_binary(note_id) do
    case read_repo().get(ContextNote, note_id) do
      %ContextNote{deleted: false} = note -> to_map(note)
      _ -> nil
    end
  end

  def target_snapshot(target_ref) when is_binary(target_ref) do
    read_repo().one(
      from(f in FeedItem,
        where:
          f.entity_id == ^target_ref and f.entity_type in ["murmur", "note", "thread", "post"] and
            f.deleted == false and f.sig_verified == true and
            (is_nil(f.visibility) or f.visibility == "public"),
        order_by: [desc: f.log_id],
        limit: 1
      )
    )
    |> case do
      nil ->
        nil

      item ->
        %{
          entity_type: item.entity_type,
          entity_id: item.entity_id,
          op_id: item.op_id,
          content_hash: content_hash(item.payload)
        }
    end
  end

  def to_map(%ContextNote{} = note) do
    %{
      note_id: note.note_id,
      author_did: note.author_did,
      canonical_author_did: note.canonical_author_did,
      target_entity_type: note.target_entity_type,
      target_entity_id: note.target_entity_id,
      target_op_id: note.target_op_id,
      target_content_hash: note.target_content_hash,
      body: note.body,
      sources: note.sources,
      board_id: note.board_id,
      created_at: note.created_at,
      updated_log_id: note.updated_log_id,
      provenance: %{
        source: note.source,
        sig_verified: true,
        signature: note.signature,
        public_key_hex: note.public_key_hex,
        verified_at: note.verified_at,
        anchor_expires_at: note.anchor_expires_at
      }
    }
  end

  defp upsert(op, payload, anchor_expires_at, pending_target_revisions) do
    with :ok <- validate_payload(payload),
         :ok <- validate_target_revision(payload, pending_target_revisions),
         :ok <- authorize_mutation(op, payload),
         {:ok, created_at} <- parse_optional_datetime(payload["createdAt"]) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      row = %ContextNote{
        note_id: op["entity_id"],
        author_did: op["author_did"],
        canonical_author_did: op["canonical_author_did"] || op["author_did"],
        target_entity_type: payload["targetEntityType"],
        target_entity_id: payload["targetEntityId"],
        target_op_id: payload["targetOpId"],
        target_content_hash: payload["targetContentHash"],
        body: String.trim(payload["body"]),
        sources: payload["sources"],
        board_id: payload["boardId"],
        created_at: created_at,
        updated_log_id: op["log_id"],
        source: "relay_firehose",
        signature: op["signature"],
        public_key_hex: op["public_key_hex"],
        verified_at: now,
        anchor_expires_at: anchor_expires_at,
        deleted: false
      }

      Repo.insert(row,
        on_conflict:
          {:replace,
           [
             :author_did,
             :canonical_author_did,
             :body,
             :sources,
             :board_id,
             :created_at,
             :updated_log_id,
             :source,
             :signature,
             :public_key_hex,
             :verified_at,
             :anchor_expires_at,
             :deleted,
             :updated_at
           ]},
        conflict_target: :note_id
      )
    else
      _ -> :noop
    end
  end

  defp validate_target_revision(payload, pending_target_revisions) do
    case Map.get(pending_target_revisions, payload["targetOpId"]) do
      {op, target_payload} ->
        if op["entity_type"] == payload["targetEntityType"] and
             op["entity_id"] == payload["targetEntityId"] and
             content_hash(target_payload) == payload["targetContentHash"] do
          :ok
        else
          :error
        end

      nil ->
        validate_stored_target_revision(payload)
    end
  end

  defp validate_stored_target_revision(payload) do
    target =
      read_repo().one(
        from(f in FeedItem,
          where:
            f.op_id == ^payload["targetOpId"] and
              f.entity_type == ^payload["targetEntityType"] and
              f.entity_id == ^payload["targetEntityId"] and
              f.deleted == false and f.sig_verified == true and
              (is_nil(f.visibility) or f.visibility == "public"),
          limit: 1
        )
      )

    case target do
      %FeedItem{} = item ->
        if content_hash(item.payload) == payload["targetContentHash"], do: :ok, else: :error

      _ ->
        :error
    end
  end

  defp mark_deleted(op) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(n in ContextNote,
        where: n.note_id == ^op["entity_id"] and n.author_did == ^op["author_did"]
      ),
      set: [deleted: true, updated_log_id: op["log_id"], updated_at: now]
    )

    :ok
  end

  defp authorize_mutation(%{"op_type" => "insert"}, _payload), do: :ok

  defp authorize_mutation(%{"op_type" => "update"} = op, payload) do
    case Repo.get(ContextNote, op["entity_id"]) do
      %ContextNote{} = existing ->
        same_target =
          existing.author_did == op["author_did"] and
            existing.target_entity_type == payload["targetEntityType"] and
            existing.target_entity_id == payload["targetEntityId"] and
            existing.target_op_id == payload["targetOpId"] and
            existing.target_content_hash == payload["targetContentHash"]

        if same_target, do: :ok, else: {:error, :retarget_forbidden}

      nil ->
        {:error, :missing_context_note}
    end
  end

  defp validate_payload(payload) do
    body = payload["body"]
    sources = payload["sources"]

    valid =
      payload["visibility"] == "public" and
        payload["targetEntityType"] in @target_types and
        present?(payload["targetEntityId"]) and present?(payload["targetOpId"]) and
        is_binary(payload["targetContentHash"]) and
        Regex.match?(@hash_pattern, payload["targetContentHash"]) and
        is_binary(body) and String.length(String.trim(body)) in 1..1000 and
        is_list(sources) and length(sources) in 1..5 and Enum.all?(sources, &valid_source?/1)

    if valid, do: :ok, else: {:error, :invalid_context_note}
  end

  defp valid_source?(%{"url" => url} = source) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        title = source["title"]
        is_nil(title) or (is_binary(title) and String.length(title) <= 200)

      _ ->
        false
    end
  end

  defp valid_source?(_), do: false
  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp parse_optional_datetime(nil), do: {:ok, nil}

  defp parse_optional_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} ->
        {:ok, %{parsed | microsecond: {elem(parsed.microsecond, 0), 6}}}

      _ ->
        {:error, :invalid_datetime}
    end
  end

  defp parse_optional_datetime(_), do: {:error, :invalid_datetime}

  defp content_hash(payload) do
    "sha256:" <>
      (:crypto.hash(:sha256, canonical_json(payload)) |> Base.encode16(case: :lower))
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

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)
end
