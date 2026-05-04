defmodule AnsibleRelay.Web.Controllers.OpsController do
  @moduledoc "Phase 2 — Op ingestion and delta pull endpoints."

  import Plug.Conn
  alias AnsibleRelay.{AbuseDetector, IdentityCache, OpStore, SigVerifier}

  @required_fields ~w(op_id author_did entity_type entity_id op_type payload signature)
  @valid_entity_types ~w(board thread post reaction)
  @valid_op_types ~w(insert update delete crdt_merge)

  # POST /api/v1/ops
  def ingest(conn, params) do
    with :ok <- validate_fields(params, @required_fields),
         :ok <- validate_enum(params["entity_type"], @valid_entity_types, "entity_type"),
         :ok <- validate_enum(params["op_type"], @valid_op_types, "op_type"),
         author_did = params["author_did"],
         :ok <- check_did_verified(author_did),
         :ok <- check_abuse_limit(author_did),
         :ok <- check_op_not_duplicate(params["op_id"]),
         public_key = IdentityCache.public_key_hex(author_did),
         message = params["op_id"] <> params["payload"],
         :ok <- check_signature(public_key, message, params["signature"]) do
      op = %{
        op_id: params["op_id"],
        author_did: author_did,
        entity_type: params["entity_type"],
        entity_id: params["entity_id"],
        op_type: params["op_type"],
        payload: params["payload"],
        signature: params["signature"],
        received_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      case OpStore.append(op) do
        {:ok, log_id} ->
          send_json(conn, 202, %{accepted: true, log_id: log_id})

        {:error, :duplicate} ->
          send_json(conn, 409, %{error: "duplicate_op_id"})
      end
    else
      {:error, :missing_fields, fields} ->
        send_json(conn, 422, %{error: "missing_required_fields", fields: fields})

      {:error, :invalid_enum, {field, value, valid}} ->
        send_json(conn, 422, %{error: "invalid_value", field: field, value: value, valid: valid})

      {:error, :unverified_did} ->
        send_json(conn, 401, %{
          error: "unverified_did",
          message: "DID not anchored. Complete Phase 1 identity anchoring first."
        })

      {:error, :duplicate_op} ->
        send_json(conn, 409, %{error: "duplicate_op_id"})

      {:error, :bad_signature} ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :rate_limited, detail} ->
        send_json(conn, 429, %{error: "rate_limited", detail: detail})
    end
  end

  # GET /api/v1/ops/delta
  def delta(conn, params) do
    cursor = parse_int(params["cursor"], 0)
    raw_limit = parse_int(params["limit"], 100)
    limit = min(raw_limit, 500)

    # Fetch one extra to determine has_more
    ops = OpStore.list(after_log_id: cursor, limit: limit + 1)
    has_more = length(ops) > limit
    visible = Enum.take(ops, limit)

    next_cursor =
      case visible do
        [] -> cursor
        list -> List.last(list).log_id
      end

    send_json(conn, 200, %{
      ops: visible,
      next_cursor: next_cursor,
      has_more: has_more
    })
  end

  # --- Private helpers ---

  defp validate_fields(params, required) do
    missing = Enum.filter(required, &(is_nil(params[&1]) or params[&1] == ""))
    if missing == [], do: :ok, else: {:error, :missing_fields, missing}
  end

  defp validate_enum(value, valid_values, field) do
    if value in valid_values,
      do: :ok,
      else: {:error, :invalid_enum, {field, value, valid_values}}
  end

  defp check_did_verified(did) do
    if IdentityCache.verified?(did), do: :ok, else: {:error, :unverified_did}
  end

  defp check_abuse_limit(did) do
    case AbuseDetector.check_did(did) do
      :ok -> :ok
      {:error, :rate_limited, detail} -> {:error, :rate_limited, detail}
    end
  end

  defp check_op_not_duplicate(op_id) do
    if OpStore.exists?(op_id), do: {:error, :duplicate_op}, else: :ok
  end

  defp check_signature(public_key, message, sig_hex) do
    if SigVerifier.verify_ed25519(public_key, message, sig_hex),
      do: :ok,
      else: {:error, :bad_signature}
  end

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end
  defp parse_int(n, _default) when is_integer(n), do: n

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
