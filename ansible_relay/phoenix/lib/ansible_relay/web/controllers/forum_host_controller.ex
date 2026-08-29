defmodule AnsibleRelay.Web.Controllers.ForumHostController do
  @moduledoc """
  Minimal Forum Host discovery surface.

  Boards are host-owned. The app stores local projections and subscriptions.
  This controller intentionally exposes a small JSON contract first; durable
  storage and full signature validation land behind the same routes.
  """

  import Plug.Conn
  require Logger
  alias AnsibleRelay.{AbuseDetector, VpVerifier}
  alias AnsibleRelay.CommunityNotes.Store, as: CommunityNotesStore

  alias AnsibleRelay.ForumHost.{
    BoardAccessPolicy,
    BoardCapability,
    BoardCapabilityRequest,
    BoardVpVerifier,
    Moderation,
    PostingGate,
    PresentationSession,
    SignedIntent,
    Store,
    TrustedMembershipIssuer
  }

  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def info(conn, _params) do
    send_json(conn, 200, Store.host_info())
  end

  def boards(conn, _params) do
    send_json(conn, 200, %{boards: Store.list_public_boards()})
  end

  # GET /api/v1/forum-host/boards/created-by/:did — boards this DID authored, so
  # a reinstalled client can re-list its own boards (subscriptions are local).
  def boards_created_by(conn, did) do
    send_json(conn, 200, %{boards: Store.list_boards_created_by(did)})
  end

  # GET /api/v1/forum-host/threads/:thread_id/preview — public metadata for a
  # shared thread link (outbound sharing loop): the web frontend's OG injector
  # uses it to render a thread-specific preview instead of falling back to the
  # board description. Removal tombstones win: a removed thread 404s with its
  # public reason code rather than leaking the stripped payload.
  def thread_preview(conn, thread_id) do
    case AnsibleRelay.OpStore.create_op("thread", thread_id) do
      nil ->
        send_json(conn, 404, %{error: "thread_not_found"})

      op ->
        board_id = decode_op_payload(op.payload)["boardId"]

        case PostingGate.get_board(board_id) do
          %{content_visibility: "public", access_policy: %{"discovery" => "public"}} ->
            case Moderation.overlay_ops([op]) do
              [%{removed: true, reason_code: reason}] ->
                send_json(conn, 404, %{error: "thread_removed", reason_code: reason})

              [visible] ->
                send_json(conn, 200, thread_preview_body(thread_id, visible))
            end

          _ ->
            send_json(conn, 404, %{error: "board_hidden"})
        end
    end
  end

  defp thread_preview_body(thread_id, op) do
    payload = decode_op_payload(op.payload)
    {reply_count, first_reply} = AnsibleRelay.OpStore.thread_reply_stats(thread_id)

    excerpt =
      case first_reply && decode_op_payload(first_reply.payload) do
        %{"content" => content} when is_binary(content) -> truncate_excerpt(content)
        _ -> nil
      end

    %{
      thread_id: thread_id,
      board_id: payload["boardId"],
      title: payload["title"],
      author_did: op.author_did,
      author_handle: author_handle(op.author_did),
      created_at: payload["createdAt"] || op.received_at,
      reply_count: reply_count,
      excerpt: excerpt,
      locked: Map.get(op, :locked, false)
    }
  end

  defp decode_op_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_op_payload(_payload), do: %{}

  defp truncate_excerpt(content) do
    trimmed = String.trim(content)
    if String.length(trimmed) > 200, do: String.slice(trimmed, 0, 200) <> "…", else: trimmed
  end

  defp author_handle(did) do
    case AnsibleRelay.DidAccountCache.get(did) do
      {:ok, %{handle: handle}} when is_binary(handle) and handle != "" -> handle
      _ -> nil
    end
  end

  # GET /api/v1/discover/boards?q=&limit=  (empty q -> browse all)
  def discover_boards(conn, params) do
    q = params["q"] || ""

    limit =
      case Integer.parse(to_string(params["limit"] || "")) do
        {n, _} -> n
        :error -> 20
      end

    send_json(conn, 200, %{boards: Store.search_boards(q, limit)})
  end

  def announcements(conn, _params) do
    send_json(conn, 200, %{announcements: Store.list_announcements("forum_host")})
  end

  def access_requirements(conn, board_id) do
    case PostingGate.get_board(board_id) do
      nil ->
        send_json(conn, 404, %{error: "board_not_found"})

      board ->
        send_json(conn, 200, %{
          board_id: Integer.to_string(board.board_id),
          forum_host_id: Store.forum_host_id(),
          host: Store.base_url(),
          policy: board.access_policy,
          policy_version: board.access_policy_version,
          content_visibility: board.content_visibility
        })
    end
  end

  def policy_history(conn, board_id) do
    case PostingGate.get_board(board_id) do
      nil ->
        send_json(conn, 404, %{error: "board_not_found"})

      board ->
        versions =
          board.hosted_board_id
          |> Store.list_board_policy_versions()
          |> Enum.map(fn version ->
            %{
              version: version.version,
              policy_hash: version.policy_hash,
              policy: version.canonical_policy,
              approval_count: map_size(version.approvals),
              effective_at: version.effective_at,
              superseded_at: version.superseded_at
            }
          end)

        send_json(conn, 200, %{board_id: board.hosted_board_id, versions: versions})
    end
  end

  def presentation_options(conn, board_id, params) do
    action = parse_access_action(params["action"] || "read")

    with board when not is_nil(board) <- PostingGate.get_board(board_id),
         {:ok, requirement} <- BoardAccessPolicy.requirement_for(board.access_policy, action),
         false <- requirement in ["public", "posting_policy", "board_moderator"],
         {:ok, nonce, state} <- PresentationSession.issue(board, Store.base_url(), action) do
      definition = presentation_definition(board, requirement)
      request_uri = oid4vp_request_uri(board, nonce, state, definition)

      send_json(conn, 200, %{
        request_uri: request_uri,
        nonce: nonce,
        state: state,
        expires_in: 120,
        policy_version: board.access_policy_version
      })
    else
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      true -> send_json(conn, 409, %{error: "credential_not_required"})
      {:error, reason} -> send_json(conn, 422, %{error: error_string(reason)})
    end
  end

  def verify_presentation(conn, board_id, params) do
    action = parse_access_action(params["action"] || "read")
    state = params["state"]
    vp_token = params["vp_token"]

    with true <- is_binary(state) and (is_binary(vp_token) or is_map(vp_token)),
         board when not is_nil(board) <- PostingGate.get_board(board_id),
         # PresentationSession predates canonical numeric board IDs and stores
         # the durable hosted-board key.  The route may use the canonical ID,
         # so consume against the resolved board's durable key; policy and
         # canonical board binding are still checked below.
         {:ok, session} <- PresentationSession.consume(state, board.hosted_board_id),
         true <-
           session.policy_version == board.access_policy_version and
             session.audience == Store.base_url() and
             session.action == Atom.to_string(action),
         {:ok, nonce} <- presentation_nonce(vp_token),
         true <- PresentationSession.matches_nonce?(session, nonce),
         {:ok, requirement} <- BoardAccessPolicy.requirement_for(board.access_policy, action),
         {:ok, result} <-
           verify_board_presentation(
             vp_token,
             board.access_policy,
             requirement,
             nonce,
             Store.base_url(),
             board_id: Integer.to_string(board.board_id),
             forum_host_id: Store.forum_host_id(),
             issuer_resolver: &TrustedMembershipIssuer.resolve/2,
             status_checker: &credential_status/2
           ),
         {:ok, capability, grant} <-
           BoardCapability.issue(
             board,
             result.pairwise_subject,
             result.device_key_thumbprint,
             capability_scopes(board, action)
           ) do
      send_json(conn, 200, %{
        board_capability: capability,
        token_type: "Bearer",
        expires_at: grant.expires_at,
        scopes: grant.scopes,
        policy_version: grant.policy_version,
        device_key_thumbprint: grant.device_key_thumbprint
      })
    else
      nil ->
        send_json(conn, 404, %{error: "board_not_found"})

      {:error, reason} ->
        # Reason codes identify a rejected access rule without logging a
        # presentation, VC, holder DID, or any other identity material.
        Logger.warning(
          "board presentation rejected board_id=#{board_id} action=#{action} reason=#{error_string(reason)}"
        )

        send_json(conn, 403, %{error: error_string(reason)})

      _ ->
        send_json(conn, 400, %{error: "invalid_presentation"})
    end
  end

  defp presentation_nonce(vp_token) when is_binary(vp_token),
    do: BoardVpVerifier.nonce(vp_token)

  defp presentation_nonce(%{"proof" => %{"challenge" => nonce}})
       when is_binary(nonce) and nonce != "",
       do: {:ok, nonce}

  defp presentation_nonce(_), do: {:error, :invalid_presentation}

  defp verify_board_presentation(
         vp_token,
         policy,
         requirement,
         nonce,
         audience,
         opts
       )
       when is_binary(vp_token) do
    BoardVpVerifier.verify(vp_token, policy, requirement, nonce, audience, opts)
  end

  defp verify_board_presentation(
         %{"holder" => holder, "deviceKeyJwk" => device_jwk} = vp,
         policy,
         requirement,
         nonce,
         audience,
         opts
       )
       when is_binary(holder) and is_map(device_jwk) do
    status_checker = Keyword.fetch!(opts, :status_checker)

    with {:ok, credential_type, vc} <-
           VpVerifier.verify_with_credential(
             holder,
             vp,
             nonce: nonce,
             audience: audience
           ),
         :active <- status_checker.(vc["credentialStatus"], DateTime.utc_now()),
         {:ok, thumbprint} <- BoardCapabilityRequest.device_thumbprint(device_jwk),
         evidence <- %{
           "credential_type" => credential_type,
           "credential_configuration_id" => nil,
           "issuer" => vc["issuer"],
           "holder_bound" => true,
           "status" => "active",
           "claims" => vc["credentialSubject"] || %{}
         },
         :ok <-
           BoardAccessPolicy.evaluate_for_requirement(
             policy,
             requirement,
             evidence
           ) do
      {:ok,
       %{
         pairwise_subject: holder,
         device_key_thumbprint: thumbprint,
         evidence: evidence
       }}
    else
      :suspended ->
        {:error, :credential_revoked}

      :revoked ->
        {:error, :credential_revoked}

      :unavailable ->
        {:error, :credential_status_unavailable}

      {:error, {:verification_stage, stage, reason}} ->
        {:error, {:verification_stage, stage, reason}}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_presentation}
    end
  end

  defp verify_board_presentation(_, _, _, _, _, _),
    do: {:error, :invalid_presentation}

  def create_board(conn, params) do
    case SignedIntent.verify_create_board(params) do
      {:ok, intent} ->
        case Store.create_board(intent) do
          {:ok, board} -> send_json(conn, 201, board)
          {:error, :duplicate_intent} -> send_json(conn, 409, %{error: "duplicate_intent"})
          {:error, error} -> send_json(conn, 422, %{error: error_string(error)})
        end

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  # POST /api/v1/forum-host/boards/:board_id/update — signed-intent board
  # management: only the board's creator DID may update title, description,
  # or posting_policy. Same fail-closed envelope checks as create_board.
  def update_board(conn, board_id, params) do
    case SignedIntent.verify_update_board(params) do
      {:ok, intent} ->
        if intent.board_id == board_id do
          apply_board_update(conn, intent)
        else
          send_json(conn, 422, %{error: "board_id_mismatch"})
        end

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  def update_board_policy(conn, board_id, params) do
    case SignedIntent.verify_update_board_policy(params) do
      {:ok, intent} when intent.board_id == board_id ->
        case Store.update_board_policy(intent) do
          {:ok, board} ->
            send_json(conn, 200, board)

          {:error, :board_not_found} ->
            send_json(conn, 404, %{error: "board_not_found"})

          {:error, reason}
          when reason in [:policy_hash_conflict, :policy_change_pending, :duplicate_intent] ->
            send_json(conn, 409, %{error: error_string(reason)})

          {:error, reason} when reason in [:not_board_creator, :not_board_governor] ->
            send_json(conn, 403, %{error: error_string(reason)})

          {:error, reason} ->
            send_json(conn, 422, %{error: error_string(reason)})
        end

      {:ok, _intent} ->
        send_json(conn, 422, %{error: "board_id_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  defp apply_board_update(conn, intent) do
    case Store.update_board(intent) do
      {:ok, board} ->
        send_json(conn, 200, board)

      {:error, :board_not_found} ->
        send_json(conn, 404, %{error: "board_not_found"})

      {:error, :not_board_creator} ->
        send_json(conn, 403, %{error: "not_board_creator"})

      {:error, :duplicate_intent} ->
        send_json(conn, 409, %{error: "duplicate_intent"})

      {:error, :policy_version_conflict} ->
        send_json(conn, 409, %{error: "policy_version_conflict"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  def create_web_thread(conn, params) do
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      send_json(conn, 409, %{
        error: "passkey_author_proof_required",
        challenge_endpoint: "/api/v1/web-publication/challenges",
        operation_endpoint: "/api/v1/web-publication/operations"
      })
    end
  end

  # --- Content reporting (web-session rail) ---

  # POST /api/v1/forum-host/web/reports
  def create_web_report(conn, params) do
    AnsibleRelay.Metrics.inc("relay_reports_total", %{rail: "web_session"})
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      result =
        Moderation.create_report(%{
          reporter_did: conn.assigns.verified_did,
          target_kind: params["target_kind"],
          target_ref: params["target_ref"],
          board_id: params["board_id"],
          reason_code: params["reason_code"],
          note: params["note"]
        })

      send_report_result(conn, result)
    end
  end

  # --- Content reporting (signed-intent rail) ---

  # POST /api/v1/forum-host/reports
  def create_report(conn, params) do
    AnsibleRelay.Metrics.inc("relay_reports_total", %{rail: "signed_intent"})

    case SignedIntent.verify_report_content(params) do
      {:ok, attrs} ->
        send_report_result(conn, Moderation.create_report(attrs))

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  # --- Community Notes (private signed ratings; public aggregate status) ---

  def rate_context_note(conn, note_id, params) do
    params = Map.put(params, "note_id", note_id)

    case SignedIntent.verify_rate_context_note(params) do
      {:ok, attrs} ->
        case CommunityNotesStore.rate(attrs) do
          {:ok, :stored, rating} ->
            send_json(conn, 201, %{rating: rating})

          {:ok, :duplicate, rating} ->
            send_json(conn, 200, %{rating: rating, duplicate: true})

          {:error, :rate_limited, detail} ->
            send_json(conn, 429, %{error: "rate_limited", detail: detail})

          {:error, error} ->
            send_json(conn, 422, %{error: error_string(error)})
        end

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error} when error in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  def context_note_status(conn, note_id) do
    case CommunityNotesStore.status(note_id) do
      {:ok, status} ->
        send_json(conn, 200, %{status: status})

      {:error, :context_note_not_found} ->
        send_json(conn, 404, %{error: "context_note_not_found"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  def context_note_statuses(conn, params) do
    case params["target_ref"] do
      target_ref when is_binary(target_ref) and target_ref != "" ->
        {:ok, statuses} = CommunityNotesStore.statuses_for_target(target_ref)
        send_json(conn, 200, %{statuses: statuses})

      _ ->
        send_json(conn, 422, %{error: "missing_target_ref"})
    end
  end

  # --- Moderation console (web-session rail, board moderators only) ---

  # GET /api/v1/forum-host/web/moderation/reports?status=open
  def list_web_moderation_reports(conn, params) do
    conn = VerifyWebSession.call(conn, ["forum:read"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      case Moderation.list_reports(conn.assigns.verified_did, params["status"] || "open") do
        {:ok, reports} -> send_json(conn, 200, %{reports: reports})
        {:error, :not_board_moderator} -> send_json(conn, 403, %{error: "not_board_moderator"})
      end
    end
  end

  # POST /api/v1/forum-host/web/moderation/actions
  def create_web_moderation_action(conn, params) do
    conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      result =
        Moderation.create_action(%{
          moderator_did: conn.assigns.verified_did,
          action: params["action"],
          target_ref: params["target_ref"],
          board_id: params["board_id"],
          reason_code: params["reason_code"],
          report_id: parse_report_id(params["report_id"])
        })

      case result do
        {:ok, action} ->
          send_json(conn, 201, %{action: action})

        {:error, :not_board_moderator} ->
          send_json(conn, 403, %{error: "not_board_moderator"})

        {:error, error} ->
          send_json(conn, 422, %{error: error_string(error)})
      end
    end
  end

  # GET /api/v1/forum-host/web/moderation/actions — the audit list.
  def list_web_moderation_actions(conn, _params) do
    conn = VerifyWebSession.call(conn, ["forum:read"], audience: Store.base_url())

    if conn.halted do
      conn
    else
      case Moderation.list_actions(conn.assigns.verified_did) do
        {:ok, actions} -> send_json(conn, 200, %{actions: actions})
        {:error, :not_board_moderator} -> send_json(conn, 403, %{error: "not_board_moderator"})
      end
    end
  end

  # GET /api/v1/forum-host/boards/:board_id/moderation-state — public:
  # tombstone refs and lock states are reason-coded and visible to everyone,
  # including the affected author (constitution Base Rule 6).
  def board_moderation_state(conn, board_id) do
    case PostingGate.get_board(board_id) do
      nil -> send_json(conn, 404, %{error: "board_not_found"})
      board -> send_json(conn, 200, Moderation.moderation_state(board.hosted_board_id))
    end
  end

  defp send_report_result(conn, result) do
    case result do
      {:ok, :created, report} ->
        send_json(conn, 201, %{report: report})

      {:ok, :duplicate, report} ->
        send_json(conn, 200, %{report: report})

      {:error, :rate_limited, _detail} ->
        send_json(conn, 429, %{error: "rate_limited"})

      {:error, error} ->
        send_json(conn, 422, %{error: error_string(error)})
    end
  end

  defp authorize_web_thread_lock(params) do
    case Map.get(params, "thread_id") do
      thread_id when is_binary(thread_id) -> Moderation.authorize_thread_post(thread_id)
      _absent -> :ok
    end
  end

  defp parse_report_id(value) when is_integer(value), do: value

  defp parse_report_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _other -> nil
    end
  end

  defp parse_report_id(_value), do: nil

  defp parse_access_action("discover"), do: :discovery
  defp parse_access_action("read"), do: :read
  defp parse_access_action("post"), do: :post
  defp parse_access_action("moderate"), do: :moderate
  defp parse_access_action("analyze"), do: :analyze
  defp parse_access_action(_), do: :invalid

  defp scope_for(:discovery), do: "discover"
  defp scope_for(action), do: Atom.to_string(action)

  defp capability_scopes(%{content_visibility: "end_to_end_encrypted"}, action)
       when action in [:read, :moderate],
       do: [scope_for(action), "key:read"]

  defp capability_scopes(_board, action), do: [scope_for(action)]

  defp presentation_definition(board, requirement) do
    rule = board.access_policy["requirements"][requirement]

    claim_fields =
      Enum.map(rule["claims"], fn claim ->
        %{
          "path" => ["$.vc.credentialSubject.#{claim["path"]}"],
          "filter" => %{"const" => claim["value"]}
        }
      end)

    %{
      "id" => "board-#{board.hosted_board_id}-policy-#{board.access_policy_version}",
      "input_descriptors" => [
        %{
          "id" => requirement,
          "format" => %{"jwt_vc_json" => %{"alg" => ["EdDSA"]}},
          "constraints" => %{
            "fields" => [
              %{
                "path" => ["$.vc.type"],
                "filter" => %{"contains" => %{"const" => rule["credential_type"]}}
              }
              | claim_fields
            ]
          }
        }
      ]
    }
  end

  defp oid4vp_request_uri(board, nonce, state, definition) do
    query =
      URI.encode_query(%{
        "client_id" => Store.base_url(),
        "response_type" => "vp_token",
        "response_mode" => "direct_post",
        "response_uri" =>
          "#{Store.base_url()}/api/v1/forum-host/boards/#{board.hosted_board_id}/presentation/verify",
        "nonce" => nonce,
        "state" => state,
        "presentation_definition" => Jason.encode!(definition)
      })

    "openid4vp://authorize?" <> query
  end

  defp credential_status(status, now) do
    module =
      Application.get_env(
        :ansible_relay,
        :board_credential_status_checker,
        AnsibleRelay.ForumHost.BitstringStatusChecker
      )

    if is_atom(module) and function_exported?(module, :check, 2),
      do: module.check(status, now),
      else: :unavailable
  end

  # board_id is optional for backward compatibility (the endpoint predates
  # board-scoped web threads), but when present it must resolve to a hosted
  # board so a gated board cannot be bypassed with a mistyped id.
  defp resolve_web_thread_board(params) do
    case Map.get(params, "board_id") || Map.get(params, "hosted_board_id") do
      nil ->
        {:ok, nil}

      board_id when is_binary(board_id) ->
        case PostingGate.get_board(board_id) do
          nil -> {:error, :board_not_found}
          board -> {:ok, board}
        end

      _invalid ->
        {:error, :board_not_found}
    end
  end

  defp error_string(error) when is_atom(error), do: Atom.to_string(error)
  defp error_string(error), do: inspect(error)

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
