defmodule AnsibleRelay.Web.Controllers.OpsController do
  @moduledoc "Phase 2 — Op ingestion and delta pull endpoints."

  import Plug.Conn

  alias AnsibleRelay.{
    AbuseDetector,
    FollowAccess,
    IdentityCache,
    IdentityWritePolicy,
    OpStore,
    SnapshotStore
  }

  alias AnsibleRelay.ForumHost.{
    BoardCapabilityRequest,
    Moderation,
    PostingGate,
    PrivateBoardKeys,
    Store
  }

  @required_fields ~w(op_id author_did entity_type entity_id op_type payload signature)
  @valid_entity_types ~w(board thread post reaction murmur note follow follow_grant profile comment)
  @valid_op_types ~w(insert update delete crdt_merge)
  # Entity kinds whose creation is gated by a hosted board's
  # posting_policy["min_post_tier"] (threads and replies alike).
  @gated_entity_types ~w(thread post)
  # Standalone content kinds (no board/thread) whose public/unlisted visibility is
  # checked as defense-in-depth before relaying. Primary enforcement is app-side.
  @content_entity_types ~w(murmur note)
  @relayable_visibilities ~w(public unlisted followers)

  # POST /api/v1/ops
  def ingest(conn, params) do
    with :ok <- validate_fields(params, @required_fields),
         :ok <- validate_enum(params["entity_type"], @valid_entity_types, "entity_type"),
         :ok <- validate_enum(params["op_type"], @valid_op_types, "op_type"),
         :ok <- validate_schema_version(params["schema_version"]),
         :ok <- check_content_visibility(params["entity_type"], params["payload"]),
         {:ok, reaction_target} <-
           reaction_target(params["entity_type"], params["op_type"], params["payload"]),
         author_did = params["author_did"],
         :ok <- check_sync_capability(conn, author_did),
         :ok <- check_did_verified(author_did),
         :ok <- check_write_algorithm(author_did),
         :ok <- check_abuse_limit(author_did),
         :ok <- check_op_not_duplicate(params["op_id"]),
         message = signing_payload(params),
         :ok <- check_signature(author_did, message, params["signature"]),
         :ok <- FollowAccess.validate_op(params),
         :ok <-
           check_original_author(
             params["entity_type"],
             params["entity_id"],
             params["op_type"],
             author_did
           ),
         :ok <-
           check_posting_gate(
             conn,
             params["entity_type"],
             params["op_type"],
             params["payload"],
             author_did
           ),
         :ok <-
           check_board_content_encryption(
             params["entity_type"],
             params["entity_id"],
             params["op_type"],
             params["payload"]
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

      case append_op(op, reaction_target) do
        {:ok, log_id} ->
          AnsibleRelay.Metrics.inc("relay_op_ingest_total", %{
            entity_type: op.entity_type,
            op_type: op.op_type
          })

          # Fire-and-forget (async cast): wake scheduling can never affect
          # the ingest response.
          AnsibleRelay.Push.WakeScheduler.op_accepted(op)
          send_json(conn, 202, %{accepted: true, log_id: log_id})

        {:error, :duplicate} ->
          send_json(conn, 409, %{error: "duplicate_op_id"})

        {:error, :active_reaction_exists} ->
          send_json(conn, 409, %{error: "active_reaction_exists"})

        {:error, :invalid_reaction_payload} ->
          send_json(conn, 422, %{error: "invalid_reaction_payload"})

        {:error, :not_original_author} ->
          send_json(conn, 403, %{error: "not_original_author"})

        {:error, :original_content_not_found} ->
          send_json(conn, 404, %{error: "original_content_not_found"})

        # A malformed payload shape (e.g. a JSON object where the store expects
        # a string column) fails the changeset cast. Treat it as bad input, not
        # a server error — otherwise the unmatched tuple raises CaseClauseError.
        {:error, :insert_failed} ->
          send_json(conn, 422, %{error: "invalid_op_payload"})
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

      {:error, reason} when reason in [:invalid_follow_request, :invalid_follow_grant] ->
        send_json(conn, 422, %{error: Atom.to_string(reason)})

      {:error, :unverified_did} ->
        send_json(conn, 401, %{
          error: "unverified_did",
          message: "DID not anchored. Complete Phase 1 identity anchoring first."
        })

      {:error, :invalid_sync_capability} ->
        send_json(conn, 401, %{error: "invalid_sync_capability"})

      {:error, :identity_key_upgrade_required} ->
        send_json(conn, 409, %{
          error: "identity_key_upgrade_required",
          expected: IdentityWritePolicy.expected()
        })

      # DB/infrastructure outage during the verification lookup: this is NOT an
      # unverified DID. Return a retryable 503 so clients back off rather than
      # (destructively) re-anchoring on a transient Postgres blip.
      {:error, :verification_unavailable} ->
        send_json(conn, 503, %{
          error: "verification_unavailable",
          message: "Identity verification is temporarily unavailable. Retry shortly.",
          retryable: true
        })

      {:error, :duplicate_op} ->
        send_json(conn, 409, %{error: "duplicate_op_id"})

      {:error, :bad_signature} ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :not_original_author} ->
        send_json(conn, 403, %{error: "not_original_author"})

      {:error, :original_content_not_found} ->
        send_json(conn, 404, %{error: "original_content_not_found"})

      {:error, :rate_limited, detail} ->
        send_json(conn, 429, %{error: "rate_limited", detail: detail})

      {:error, :posting_requires_tier, required_tier, current_tier} ->
        send_json(conn, 403, %{
          error: "posting_requires_tier",
          required_tier: required_tier,
          current_tier: current_tier
        })

      {:error, reason}
      when reason in [
             :board_capability_required,
             :invalid_board_capability,
             :capability_expired,
             :board_capability_replay
           ] ->
        send_json(conn, 403, %{error: Atom.to_string(reason)})

      {:error, :thread_locked, reason_code} ->
        send_json(conn, 403, %{error: "thread_locked", reason_code: reason_code})

      {:error, reason}
      when reason in [
             :encrypted_content_not_allowed,
             :private_board_rotation_required,
             :private_board_plaintext_forbidden,
             :invalid_private_content_envelope
           ] ->
        send_json(conn, 422, %{error: Atom.to_string(reason)})
    end
  end

  defp check_sync_capability(conn, did) do
    if AnsibleRelay.WebauthnSync.enforcement_enabled?(),
      do: AnsibleRelay.WebauthnSync.authorize(conn, did),
      else: :ok
  end

  defp check_original_author(_entity_type, _entity_id, "insert", _author_did), do: :ok

  defp check_original_author(entity_type, entity_id, op_type, author_did)
       when op_type in ["update", "delete"] and
              entity_type in ["thread", "post", "comment", "reaction"] do
    case OpStore.create_op_author(entity_type, entity_id) do
      ^author_did ->
        :ok

      nil ->
        {:error, :original_content_not_found}

      original_author ->
        if AnsibleRelay.Identity.MigrationStore.equivalent?(original_author, author_did),
          do: :ok,
          else: {:error, :not_original_author}
    end
  end

  defp check_original_author(_entity_type, _entity_id, _op_type, _author_did), do: :ok

  # GET /api/v1/ops/delta
  def delta(conn, params) do
    AnsibleRelay.Metrics.inc("relay_delta_requests_total")

    AnsibleRelay.Metrics.time("relay_delta_request_duration_seconds", fn ->
      do_delta(conn, params)
    end)
  end

  defp do_delta(conn, params) do
    cursor = parse_int(params["cursor"], 0)
    raw_limit = parse_int(params["limit"], 100)
    limit = min(raw_limit, 500)

    # Fetch one extra to determine has_more
    ops = OpStore.list(after_log_id: cursor, limit: limit + 1)
    has_more = length(ops) > limit
    scanned = Enum.take(ops, limit)
    visible = Enum.filter(scanned, &public_op?/1)

    next_cursor =
      case scanned do
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

  def board_delta(conn, board_id, params) do
    with board when not is_nil(board) <- PostingGate.get_board(board_id),
         {:ok, requirement} <-
           AnsibleRelay.ForumHost.BoardAccessPolicy.requirement_for(board.access_policy, :read),
         :ok <- authorize_board_read(conn, board, requirement) do
      cursor = parse_int(params["cursor"], 0)
      limit = min(parse_int(params["limit"], 100), 500)

      {board_ops, next_cursor, has_more} =
        scan_board_ops(board.hosted_board_id, cursor, limit, [])

      page =
        board_ops
        |> Enum.take(limit)
        |> Enum.map(&attach_public_key/1)

      send_json(conn, 200, %{
        ops: Moderation.overlay_ops(page),
        next_cursor: next_cursor,
        has_more: has_more
      })
    else
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      {:error, reason} -> send_json(conn, 403, %{error: Atom.to_string(reason)})
    end
  end

  # Board ops are encoded inside the signed payload rather than indexed in a
  # dedicated SQL column. Scan the global cursor monotonically until this
  # board has a full page (plus one) or the settled log ends. The returned
  # cursor always represents every row inspected, including unrelated rows,
  # so sparse boards cannot stall forever and no matching op is skipped.
  defp scan_board_ops(board_id, cursor, target, collected) do
    batch = OpStore.list(after_log_id: cursor, limit: 500)

    {matches, scanned_cursor, full?} =
      Enum.reduce_while(batch, {collected, cursor, false}, fn op, {items, _cursor, _} ->
        items = if op_board_id(op) == board_id, do: [op | items], else: items

        if length(items) >= target do
          {:halt, {items, op.log_id, true}}
        else
          {:cont, {items, op.log_id, false}}
        end
      end)

    cond do
      full? -> {Enum.reverse(matches), scanned_cursor, true}
      length(batch) < 500 -> {Enum.reverse(matches), scanned_cursor, false}
      true -> scan_board_ops(board_id, scanned_cursor, target, matches)
    end
  end

  defp authorize_board_read(_conn, _board, "public"), do: :ok

  defp authorize_board_read(conn, board, _requirement) do
    case BoardCapabilityRequest.authorize(conn, board.hosted_board_id, "read") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp public_op?(op) do
    case op_board_id(op) do
      nil ->
        standalone_public_op?(op)

      board_id ->
        case PostingGate.get_board(board_id) do
          nil ->
            true

          %{
            content_visibility: "public",
            access_policy: %{"read" => %{"requirement" => "public"}}
          } ->
            true

          _ ->
            false
        end
    end
  end

  defp standalone_public_op?(%{entity_type: type, payload: payload})
       when type in @content_entity_types do
    case decode_payload(payload) do
      {:ok, %{} = decoded} -> decoded["visibility"] in [nil, "public", "unlisted"]
      _ -> type == "murmur"
    end
  end

  defp standalone_public_op?(_op), do: true

  defp op_board_id(op) do
    case decode_payload(op.payload) do
      {:ok, %{} = decoded} -> decoded["boardId"] || decoded["board_id"]
      _ -> nil
    end
  end

  # GET /api/v1/ops/snapshot
  #
  # Phase 2.3 — returns the latest relay-signed snapshot (or the newest snapshot
  # at/before `?cursor=`). A consumer folds this snapshot then applies
  # `GET /api/v1/ops/delta?cursor=<snapshot.cursor>` to reconstruct the full op
  # set without replaying history. The snapshot is independently verifiable:
  # recompute the digest from the ops + recompute the CID + check the Ed25519
  # signature against `signing_public_key_hex`.
  def snapshot(conn, params) do
    if Store.protected_boards_exist?() or OpStore.followers_content_exists?() do
      send_json(conn, 409, %{error: "public_snapshot_unavailable_with_protected_boards"})
    else
      do_snapshot(conn, params)
    end
  end

  defp do_snapshot(conn, params) do
    snapshot =
      case parse_optional_int(params["cursor"]) do
        nil -> SnapshotStore.latest()
        cursor -> SnapshotStore.at_or_before(cursor)
      end

    case snapshot do
      nil ->
        send_json(conn, 404, %{error: "no_snapshot_available"})

      %{} = snap ->
        send_json(conn, 200, %{snapshot: snap})
    end
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

  # Distinguishes three outcomes so a DB outage never masquerades as an
  # unverified DID: a live verified DID (:ok), a genuine unknown/expired DID
  # (401 unverified_did), and a DB/infrastructure outage (503, retryable).
  defp check_did_verified(did) do
    case IdentityCache.get(did) do
      {:ok, %{expires_at: expires_at}} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          :ok
        else
          {:error, :unverified_did}
        end

      :not_found ->
        {:error, :unverified_did}

      {:error, :unavailable} ->
        {:error, :verification_unavailable}
    end
  end

  defp check_abuse_limit(did) do
    case AbuseDetector.check_did(did) do
      :ok ->
        :ok

      {:error, :rate_limited, detail} ->
        AnsibleRelay.Metrics.inc("relay_abuse_rejections_total", %{subject_type: "did"})
        {:error, :rate_limited, detail}
    end
  end

  defp check_write_algorithm(did) do
    case IdentityCache.get(did) do
      {:ok, entry} ->
        if IdentityWritePolicy.allowed?(Map.get(entry, :signing_algorithm, "ed25519")),
          do: :ok,
          else: {:error, :identity_key_upgrade_required}

      _ ->
        {:error, :identity_key_upgrade_required}
    end
  end

  defp check_op_not_duplicate(op_id) do
    if OpStore.exists?(op_id), do: {:error, :duplicate_op}, else: :ok
  end

  defp append_op(%{entity_type: entity_type, op_type: op_type} = op)
       when entity_type in ["thread", "post", "comment", "reaction"] and
              op_type in ["update", "delete"],
       do: OpStore.append_author_mutation(op)

  defp append_op(op), do: OpStore.append(op)

  defp append_op(%{entity_type: "reaction", op_type: "insert"} = op, {target_type, target_id}),
    do: OpStore.append_reaction_insert(op, target_type, target_id)

  defp append_op(op, _reaction_target), do: append_op(op)

  defp reaction_target("reaction", op_type, payload) when op_type in ["insert", "update"] do
    with {:ok, %{} = map} <- decode_payload(payload),
         target_type when target_type in ["thread", "post"] <- map["targetType"],
         target_id when is_binary(target_id) and target_id != "" <- map["targetId"],
         reaction_type when reaction_type in ["happy", "sad", "thumbsUp", "angry"] <-
           map["reactionType"] do
      {:ok, {target_type, target_id}}
    else
      _ -> {:error, :invalid_reaction_payload}
    end
  end

  defp reaction_target("reaction", "delete", payload) do
    with {:ok, %{} = map} <- decode_payload(payload),
         target_type when target_type in ["thread", "post"] <- map["targetType"],
         target_id when is_binary(target_id) and target_id != "" <- map["targetId"] do
      {:ok, {target_type, target_id}}
    else
      _ -> {:error, :invalid_reaction_payload}
    end
  end

  defp reaction_target(_, _, _), do: {:ok, nil}

  # Thread/post creation in a hosted board must satisfy that board's
  # posting_policy["min_post_tier"]. The author's tier is resolved at
  # acceptance time (never cached); ops that do not target a board hosted
  # here pass through untouched. Runs after signature verification so the
  # response never discloses a tier for an unauthenticated DID.
  defp check_posting_gate(conn, entity_type, "insert", payload, author_did)
       when entity_type in @gated_entity_types do
    decoded =
      case decode_payload(payload) do
        {:ok, %{} = value} -> value
        _ -> %{}
      end

    board_id = decoded["boardId"] || decoded["board_id"]

    if is_binary(board_id) do
      case PostingGate.get_board(board_id) do
        nil ->
          :ok

        board ->
          if entity_type == "thread" and is_map(decoded["poll"]) do
            PostingGate.authorize_poll_creation(conn, board, author_did)
          else
            PostingGate.authorize_board_post(conn, board, author_did)
          end
      end
    else
      :ok
    end
  end

  defp check_posting_gate(_conn, _entity_type, _op_type, _payload, _author_did), do: :ok

  defp check_board_content_encryption(entity_type, entity_id, op_type, payload)
       when entity_type in @gated_entity_types and op_type != "delete" do
    case decode_payload(payload) do
      {:ok, %{} = decoded} ->
        board_id = decoded["boardId"] || decoded["board_id"]

        case PostingGate.get_board(board_id) do
          nil ->
            :ok

          board ->
            PrivateBoardKeys.validate_content_envelope(board, entity_type, entity_id, decoded)
        end

      _ ->
        # Legacy/non-board ops may contain opaque payloads. Encryption rules
        # apply only after a hosted board can be resolved from a JSON object.
        :ok
    end
  end

  defp check_board_content_encryption(_entity_type, _entity_id, _op_type, _payload), do: :ok

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

  defp check_signature(author_did, message, sig_hex) do
    if IdentityCache.verify_signature(author_did, message, sig_hex) do
      AnsibleRelay.Metrics.inc("relay_signature_verifications_total", %{result: "pass"})
      :ok
    else
      AnsibleRelay.Metrics.inc("relay_signature_verifications_total", %{result: "fail"})
      {:error, :bad_signature}
    end
  end

  defp attach_public_key(%{author_did: author_did} = op) do
    signing_algorithm =
      case IdentityCache.get(author_did) do
        {:ok, entry} -> Map.get(entry, :signing_algorithm, "ed25519")
        _ -> "ed25519"
      end

    op
    |> Map.put(:public_key_hex, IdentityCache.public_key_hex(author_did))
    |> Map.put(:signing_algorithm, signing_algorithm)
    # Keep the signed author DID intact, while allowing read-model consumers to
    # collapse only a completed, dual-signed DID v1 migration for presentation.
    |> Map.put(
      :canonical_author_did,
      AnsibleRelay.Identity.MigrationStore.canonical_did(author_did)
    )
    |> Map.put(:reputation_tier, AnsibleRelay.DidAccountCache.reputation_tier(author_did))
    |> attach_public_profile_credentials()
  end

  defp attach_public_profile_credentials(%{entity_type: "profile"} = op) do
    selected =
      with {:ok, decoded} <- Base.decode64(op.payload),
           {:ok, %{} = payload} <- Jason.decode(decoded),
           types when is_list(types) <- payload["credentialTypes"] do
        Enum.filter(types, &is_binary/1)
      else
        _ -> []
      end

    credentials =
      AnsibleRelay.Identity.PublicProfileCredentialStore.list_public(
        op.author_did,
        selected
      )

    Map.put(op, :public_profile_credentials, credentials)
  end

  defp attach_public_profile_credentials(op), do: op

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

  defp parse_optional_int(nil), do: nil

  defp parse_optional_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_optional_int(n) when is_integer(n), do: n
  defp parse_optional_int(_), do: nil

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
