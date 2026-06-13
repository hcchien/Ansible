defmodule AnsibleRelay.Web.Controllers.OpsController do
  @moduledoc "Phase 2 — Op ingestion and delta pull endpoints."

  import Plug.Conn
  alias AnsibleRelay.{AbuseDetector, IdentityCache, OpStore, SigVerifier}
  alias AnsibleRelay.ForumHost.{Moderation, PostingGate}

  @required_fields ~w(op_id author_did entity_type entity_id op_type payload signature)
  @valid_entity_types ~w(board thread post reaction murmur note follow profile)
  @valid_op_types ~w(insert update delete crdt_merge)
  # Entity kinds whose creation is gated by a hosted board's
  # posting_policy["min_post_tier"] (threads and replies alike).
  @gated_entity_types ~w(thread post)
  # Standalone content kinds (no board/thread) whose public/unlisted visibility is
  # checked as defense-in-depth before relaying. Primary enforcement is app-side.
  @content_entity_types ~w(murmur note)
  @relayable_visibilities ~w(public unlisted)

  # POST /api/v1/ops
  def ingest(conn, params) do
    with :ok <- validate_fields(params, @required_fields),
         :ok <- validate_enum(params["entity_type"], @valid_entity_types, "entity_type"),
         :ok <- validate_enum(params["op_type"], @valid_op_types, "op_type"),
         :ok <- validate_schema_version(params["schema_version"]),
         :ok <- check_content_visibility(params["entity_type"], params["payload"]),
         author_did = params["author_did"],
         :ok <- check_did_verified(author_did),
         :ok <- check_abuse_limit(author_did),
         :ok <- check_op_not_duplicate(params["op_id"]),
         public_key = IdentityCache.public_key_hex(author_did),
         message = signing_payload(params),
         :ok <- check_signature(public_key, message, params["signature"]),
         :ok <-
           check_posting_gate(
             params["entity_type"],
             params["op_type"],
             params["payload"],
             author_did
           ),
         # Lock gate: a locked thread accepts no new post intents. Runs at
         # the same chokepoint as the posting gate so signed ops and
         # web-session writes share the reason-coded 403 contract.
         :ok <- check_thread_lock(params["entity_type"], params["op_type"], params["payload"]) do
      op = %{
        op_id: params["op_id"],
        author_did: author_did,
        entity_type: params["entity_type"],
        entity_id: params["entity_id"],
        op_type: params["op_type"],
        payload: params["payload"],
        signature: params["signature"],
        schema_version: params["schema_version"] || 1,
        received_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      case OpStore.append(op) do
        {:ok, log_id} ->
          # Fire-and-forget (async cast): wake scheduling can never affect
          # the ingest response.
          AnsibleRelay.Push.WakeScheduler.op_accepted(op)
          send_json(conn, 202, %{accepted: true, log_id: log_id})

        {:error, :duplicate} ->
          send_json(conn, 409, %{error: "duplicate_op_id"})
      end
    else
      {:error, :missing_fields, fields} ->
        send_json(conn, 422, %{error: "missing_required_fields", fields: fields})

      {:error, :invalid_enum, {field, value, valid}} ->
        send_json(conn, 422, %{error: "invalid_value", field: field, value: value, valid: valid})

      {:error, :invalid_schema_version, value} ->
        send_json(conn, 422, %{
          error: "invalid_schema_version",
          value: value,
          max_supported: AnsibleRelay.Protocol.current_version()
        })

      {:error, :private_content} ->
        send_json(conn, 422, %{error: "private_content_not_relayable"})

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

      {:error, :posting_requires_tier, required_tier, current_tier} ->
        send_json(conn, 403, %{
          error: "posting_requires_tier",
          required_tier: required_tier,
          current_tier: current_tier
        })

      {:error, :thread_locked, reason_code} ->
        send_json(conn, 403, %{error: "thread_locked", reason_code: reason_code})
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

    # Moderation overlay: removed posts are served as content-stripped,
    # reason-coded tombstones and locked threads carry their lock state. Only
    # this host's projection changes — the stored op rows are untouched.
    ops_with_overlay =
      visible
      |> Enum.map(&attach_public_key/1)
      |> Moderation.overlay_ops()

    send_json(conn, 200, %{
      ops: ops_with_overlay,
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

  # Optional op payload format version (Phase 0 — API versioning). Absent
  # means 1 (the only version that exists today); when present it must be an
  # integer between 1 and the relay's current protocol version, so a future
  # client can never store an op this relay does not understand.
  defp validate_schema_version(nil), do: :ok

  defp validate_schema_version(version) when is_integer(version) and version >= 1 do
    if version <= AnsibleRelay.Protocol.current_version() do
      :ok
    else
      {:error, :invalid_schema_version, version}
    end
  end

  defp validate_schema_version(version), do: {:error, :invalid_schema_version, version}

  # Defense-in-depth: standalone content (murmur/note) may only be relayed when
  # public/unlisted. Notes must carry an explicit relayable visibility; murmurs
  # have no visibility field and are accepted unless an explicit private marker is
  # present. Primary enforcement is at the author's app publish boundary.
  defp check_content_visibility(entity_type, payload) when entity_type in @content_entity_types do
    case decode_payload(payload) do
      {:ok, %{} = map} ->
        case Map.get(map, "visibility") do
          vis when is_binary(vis) ->
            if vis in @relayable_visibilities, do: :ok, else: {:error, :private_content}

          nil ->
            if entity_type == "note", do: {:error, :private_content}, else: :ok
        end

      _ ->
        if entity_type == "note", do: {:error, :private_content}, else: :ok
    end
  end

  defp check_content_visibility(_entity_type, _payload), do: :ok

  defp decode_payload(payload) when is_map(payload), do: {:ok, payload}

  # Payloads may arrive as raw JSON or, per the app's CrdtOpBuilder convention,
  # as base64-encoded JSON. Try both before giving up.
  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} ->
        {:ok, decoded}

      _ ->
        case Base.decode64(payload) do
          {:ok, raw} ->
            case Jason.decode(raw) do
              {:ok, decoded} -> {:ok, decoded}
              _ -> :error
            end

          :error ->
            :error
        end
    end
  end

  defp decode_payload(_payload), do: :error

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

  # Thread/post creation in a hosted board must satisfy that board's
  # posting_policy["min_post_tier"]. The author's tier is resolved at
  # acceptance time (never cached); ops that do not target a board hosted
  # here pass through untouched. Runs after signature verification so the
  # response never discloses a tier for an unauthenticated DID.
  defp check_posting_gate(entity_type, "insert", payload, author_did)
       when entity_type in @gated_entity_types do
    board_id =
      case decode_payload(payload) do
        {:ok, %{} = decoded} -> decoded["boardId"] || decoded["board_id"]
        _ -> nil
      end

    if is_binary(board_id) do
      PostingGate.authorize_post(board_id, author_did)
    else
      :ok
    end
  end

  defp check_posting_gate(_entity_type, _op_type, _payload, _author_did), do: :ok

  # New post inserts into a locked thread are rejected with the lock's reason
  # code. Thread inserts are new threads, which cannot be locked yet.
  defp check_thread_lock("post", "insert", payload) do
    thread_id =
      case decode_payload(payload) do
        {:ok, %{} = decoded} -> decoded["threadId"] || decoded["thread_id"]
        _ -> nil
      end

    Moderation.authorize_thread_post(thread_id)
  end

  defp check_thread_lock(_entity_type, _op_type, _payload), do: :ok

  defp check_signature(public_key, message, sig_hex) do
    if SigVerifier.verify_ed25519(public_key, message, sig_hex),
      do: :ok,
      else: {:error, :bad_signature}
  end

  defp attach_public_key(%{author_did: author_did} = op) do
    op
    |> Map.put(:public_key_hex, IdentityCache.public_key_hex(author_did))
    |> Map.put(:reputation_tier, AnsibleRelay.DidAccountCache.reputation_tier(author_did))
  end

  defp signing_payload(params) do
    %{
      "author_did" => params["author_did"],
      "entity_id" => params["entity_id"],
      "entity_type" => params["entity_type"],
      "op_id" => params["op_id"],
      "op_type" => params["op_type"],
      "payload" => params["payload"]
    }
    |> canonical_json()
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

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

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
