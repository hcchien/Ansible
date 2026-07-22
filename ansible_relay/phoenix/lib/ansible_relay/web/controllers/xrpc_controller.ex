defmodule AnsibleRelay.Web.Controllers.XrpcController do
  @moduledoc """
  AT Protocol XRPC endpoints.

  POST /xrpc/com.atproto.repo.createRecord   — create a repo record
  GET  /xrpc/com.atproto.identity.resolveHandle — resolve handle to DID
  """

  alias AnsibleRelay.{AbuseDetector, DidAccountCache, SigVerifier, OpStore}

  # POST /xrpc/com.atproto.repo.createRecord
  def create_record(conn, params) do
    with {:ok, repo} <- require_field(params, "repo"),
         {:ok, collection} <- require_field(params, "collection"),
         {:ok, record} <- require_record(params),
         :ok <- validate_public_record(collection, record),
         {:ok, commit_sig} <- require_field(params, "commit_sig") do
      # Single ETS read — avoids TOCTOU between active?/1 and public_key_hex/1
      case DidAccountCache.get(repo) do
        :not_found ->
          send_json(conn, 401, %{error: "unregistered_did"})

        # DB/infrastructure outage — not an unregistered DID. Return a retryable
        # 503 so a client doesn't (destructively) re-anchor on a transient blip.
        {:error, :unavailable} ->
          send_json(conn, 503, %{error: "verification_unavailable", retryable: true})

        {:ok, %{expires_at: exp} = entry} ->
          if DateTime.compare(DateTime.utc_now(), exp) == :lt do
            create_record_for_active_did(conn, repo, collection, record, commit_sig, entry)
          else
            # DID entry exists but has expired
            send_json(conn, 401, %{error: "unregistered_did"})
          end
      end
    else
      {:error, {:missing_field, field}} ->
        send_json(conn, 422, %{error: "missing_fields", field: field})

      {:error, :invalid_record} ->
        send_json(conn, 422, %{error: "missing_fields", detail: "record must be a map"})

      {:error, {:invalid_record, detail}} ->
        send_json(conn, 422, %{error: "invalid_record", detail: detail})
    end
  end

  defp create_record_for_active_did(
         conn,
         repo,
         collection,
         record,
         commit_sig,
         entry
       ) do
    case AbuseDetector.check_did(repo) do
      {:error, :rate_limited, detail} ->
        send_json(conn, 429, %{error: "rate_limited", detail: detail})

      :ok ->
        do_create_record(conn, repo, collection, record, commit_sig, entry)
    end
  end

  defp do_create_record(conn, repo, collection, record, commit_sig, entry) do
    record_json = Jason.encode!(record)

    if SigVerifier.verify_identity(
         Map.get(entry, :signing_algorithm, "ed25519"),
         entry.public_key_hex,
         record_json,
         commit_sig
       ) do
      rkey = tid()
      # TODO(P2): replace with real DAG-CBOR CID from Rustler NIF
      cid = "bafyreistub#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}"
      uri = "at://#{repo}/#{collection}/#{rkey}"

      op = %{
        op_id: rkey,
        author_did: repo,
        entity_type: "atproto_record",
        entity_id: uri,
        op_type: "insert",
        payload: record_json,
        signature: commit_sig,
        received_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      case OpStore.append(op) do
        {:ok, _log_id} ->
          send_json(conn, 200, %{uri: uri, cid: cid})

        {:error, :duplicate} ->
          send_json(conn, 409, %{error: "duplicate_record"})
      end
    else
      send_json(conn, 401, %{error: "invalid_sig"})
    end
  end

  # GET /xrpc/com.atproto.identity.resolveHandle
  def resolve_handle(conn, params) do
    handle = Map.get(params, "handle", "")

    if handle == "" do
      send_json(conn, 422, %{error: "missing_fields", field: "handle"})
    else
      case DidAccountCache.get_by_handle(handle) do
        {:ok, did} ->
          send_json(conn, 200, %{did: did})

        :not_found ->
          send_json(conn, 404, %{error: "handle_not_found"})
      end
    end
  end

  # --- Helpers ---

  defp require_field(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing_field, key}}
      "" -> {:error, {:missing_field, key}}
      val -> {:ok, val}
    end
  end

  defp require_record(params) do
    case Map.get(params, "record") do
      nil -> {:error, {:missing_field, "record"}}
      val when is_map(val) -> {:ok, val}
      _ -> {:error, :invalid_record}
    end
  end

  defp validate_public_record(collection, record) do
    with :ok <- validate_collection_type(collection, record),
         :ok <- reject_private_only_fields(record),
         :ok <- validate_required_fields(collection, record) do
      :ok
    end
  end

  defp validate_collection_type(collection, record) do
    case Map.get(record, "$type") do
      ^collection -> :ok
      nil -> {:error, {:missing_field, "$type"}}
      _ -> {:error, {:invalid_record, "collection must match record $type"}}
    end
  end

  defp reject_private_only_fields(record) do
    private_fields = ["privateTags", "inputSnapshot", "outputSnapshot"]

    case Enum.find(private_fields, &Map.has_key?(record, &1)) do
      nil -> :ok
      field -> {:error, {:invalid_record, "#{field} is private-only"}}
    end
  end

  defp validate_required_fields("io.trisaura.post", record),
    do: require_record_fields(record, ["text", "createdAt"])

  defp validate_required_fields("io.trisaura.murmur", record),
    do: require_record_fields(record, ["text", "createdAt"])

  defp validate_required_fields("io.trisaura.note", record),
    do: require_record_fields(record, ["body", "visibility", "createdAt"])

  defp validate_required_fields("io.trisaura.discussion", record) do
    require_record_fields(record, [
      "title",
      "body",
      "discussionShape",
      "participationPolicy",
      "forkPolicy",
      "consensusState",
      "createdAt",
      "updatedAt"
    ])
  end

  defp validate_required_fields("io.trisaura.contentRelation", record),
    do: require_record_fields(record, ["from", "to", "relationType", "createdAt"])

  defp validate_required_fields("io.trisaura.transformation", record),
    do:
      require_record_fields(record, [
        "sourceRefs",
        "targetRef",
        "targetMode",
        "providerType",
        "status",
        "createdAt"
      ])

  defp validate_required_fields("io.trisaura.projection", record),
    do:
      require_record_fields(record, [
        "source",
        "target",
        "projectedExcerpt",
        "participationPolicy",
        "ownershipTransferAcknowledged",
        "createdAt"
      ])

  defp validate_required_fields(_collection, _record), do: :ok

  defp require_record_fields(record, fields) do
    case Enum.find(fields, &blank?(Map.get(record, &1))) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?([]), do: true
  defp blank?(_), do: false

  # Generate a timestamp-based TID (AT Protocol record key)
  defp tid do
    now_us = System.os_time(:microsecond)
    rand = :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned()
    "#{now_us}#{rem(rand, 1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")}"
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
