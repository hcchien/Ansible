defmodule AnsibleRelay.Web.Controllers.IdentityAnchorController do
  @moduledoc """
  Task 4 (relay) — self-certifying identity anchor endpoints.

  Implements the re-anchor protocol (design §Re-Anchor Protocol): rotation
  and device_change are immediate (the old key / an enrolled device key is
  present — possession is authority); recovery is held in a grace window with
  an all-devices identity alert and a veto-to-freeze path (hijack resistance,
  conflict-priority #1).

  Contract:

    * POST /api/v1/identity/anchor        — submit an anchor object
    * GET  /api/v1/identity/anchor/:did   — the active anchor (the cache)
    * POST /api/v1/identity/anchor/promote — promote grace-expired pendings
    * POST /api/v1/identity/anchor/veto   — veto a pending → freeze account
  """

  import Plug.Conn

  alias AnsibleRelay.Identity.{AnchorStore, FederatedResolver}

  # POST /api/v1/identity/anchor
  def submit(conn, params) do
    {anchor, recovery_proof} = split_anchor(params)

    case AnchorStore.submit(anchor, recovery_proof: recovery_proof) do
      {:ok, :active, row} ->
        send_json(conn, success_status(row.reason), %{
          state: "active",
          anchor_cid: row.anchor_cid
        })

      {:ok, :pending, row} ->
        send_json(conn, 202, %{
          state: "pending",
          anchor_cid: row.anchor_cid,
          grace_until: DateTime.to_iso8601(row.grace_until)
        })

      {:error, :malformed} ->
        send_json(conn, 422, %{error: "malformed_anchor"})

      {:error, :unknown_reason} ->
        send_json(conn, 422, %{error: "unknown_reason"})

      {:error, :unsupported_signing_algorithm} ->
        send_json(conn, 422, %{
          error: "unsupported_signing_algorithm",
          expected: AnsibleRelay.IdentityWritePolicy.expected()
        })

      {:error, :did_mismatch} ->
        send_json(conn, 422, %{error: "did_mismatch"})

      {:error, :invalid_signature} ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :invalid_attestation} ->
        send_json(conn, 401, %{error: "invalid_attestation"})

      {:error, :invalid_recovery_proof} ->
        send_json(conn, 401, %{error: "invalid_recovery_proof"})

      {:error, :conflict} ->
        send_json(conn, 409, %{error: "conflict"})

      {:error, :chain_mismatch} ->
        send_json(conn, 409, %{error: "chain_mismatch"})

      {:error, :locked} ->
        send_json(conn, 423, %{error: "account_frozen"})
    end
  end

  # `initial` is a fresh registration → 201 Created; rotation/device_change
  # replace an existing active anchor → 200 OK.
  defp success_status("initial"), do: 201
  defp success_status(_), do: 200

  # GET /api/v1/identity/anchor/:did/pending — the veto UX on enrolled
  # devices polls this to learn a recovery re-anchor is in its grace window;
  # `canonical_body` is exactly what a veto signature must sign.
  def pending(conn, %{"did" => did}) do
    case AnchorStore.get_pending(did) do
      {:ok, pending} -> send_json(conn, 200, pending)
      {:error, :not_found} -> send_json(conn, 404, %{error: "no_pending_anchor"})
    end
  end

  # GET /api/v1/identity/anchor/:did
  def show(conn, %{"did" => did}) do
    case AnchorStore.get_active(did) do
      {:ok, object} ->
        # Consumers that must make a security decision (such as Issuer) need
        # the byte-exact signed message, not an unauthenticated key cache.
        # This is public identity material; it contains no passport data.
        send_json(conn, 200, Map.put(object, "canonical_body", AnchorStore.canonical_body(object)))

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "anchor_not_found"})

      {:error, :locked} ->
        send_json(conn, 423, %{error: "account_frozen"})
    end
  end

  # GET /api/v1/identity/did/:did — resolve a did:elix to a W3C DID document,
  # projected from the active anchor (the `did:elix` method's resolution
  # output): the identity key as the verification method, this relay as the
  # service endpoint, and the verifiable aliases (handle, did:key, optional
  # did:plc). Self-certifying: the underlying anchor at
  # GET /api/v1/identity/anchor/:did lets any party re-verify independently.
  def resolve_did(conn, %{"did" => did}) do
    case FederatedResolver.resolve(did) do
      {:ok, object, source} ->
        conn
        |> put_resp_header("x-ansible-resolved-via", resolved_via(source))
        |> send_json(200, did_document(conn, object))

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "did_not_found"})

      {:error, :locked} ->
        send_json(conn, 423, %{error: "account_frozen"})
    end
  end

  defp resolved_via(:local), do: "local"
  defp resolved_via({:peer, peer}), do: "peer:#{peer}"

  # POST /api/v1/identity/anchor/promote — internal/cron-able.
  def promote(conn, _params) do
    {:ok, promoted} = AnchorStore.promote_due()
    send_json(conn, 200, %{promoted: promoted})
  end

  # POST /api/v1/identity/anchor/veto
  def veto(conn, params) do
    did = params["did"]
    cid = params["pending_anchor_cid"]
    sig = params["veto_sig"]

    cond do
      not is_binary(did) or not is_binary(cid) or not is_binary(sig) ->
        send_json(conn, 422, %{error: "malformed_veto"})

      true ->
        case AnchorStore.veto(did, cid, sig) do
          :ok ->
            send_json(conn, 200, %{state: "vetoed", frozen: true})

          {:error, :not_found} ->
            send_json(conn, 404, %{error: "pending_anchor_not_found"})

          {:error, :invalid_signature} ->
            send_json(conn, 401, %{error: "invalid_signature"})

          {:error, :locked} ->
            send_json(conn, 423, %{error: "account_frozen"})
        end
    end
  end

  # --- helpers ---

  # The request body IS the anchor object JSON, with an optional sibling
  # `recovery_proof`. Strip it so it never pollutes the canonical body.
  defp split_anchor(params) when is_map(params) do
    {Map.delete(params, "recovery_proof"), params["recovery_proof"]}
  end

  # Project a W3C DID document from the active-anchor object map.
  defp did_document(conn, object) do
    did = object["did"]
    aka = object["also_known_as"] || []
    vm_id = "#{did}#identity"

    verification_method =
      case did_key_multibase(aka) do
        nil ->
          []

        multibase ->
          [
            %{
              "id" => vm_id,
              "type" => "Ed25519VerificationKey2020",
              "controller" => did,
              "publicKeyMultibase" => multibase
            }
          ]
      end

    %{
      "@context" => ["https://www.w3.org/ns/did/v1"],
      "id" => did,
      "alsoKnownAs" => aka,
      "verificationMethod" => verification_method,
      "authentication" => Enum.map(verification_method, & &1["id"]),
      "assertionMethod" => Enum.map(verification_method, & &1["id"]),
      "service" => [
        %{
          "id" => "#{did}#ansible_relay",
          "type" => "AnsibleRelay",
          "serviceEndpoint" => relay_endpoint(conn)
        }
      ]
    }
  end

  # The `did:key` alias carries the multibase form of the identity key; the
  # DID document's `publicKeyMultibase` is exactly that suffix.
  defp did_key_multibase(also_known_as) do
    Enum.find_value(also_known_as, fn
      "did:key:" <> multibase -> multibase
      _ -> nil
    end)
  end

  defp relay_endpoint(conn) do
    case Application.get_env(:ansible_relay, :public_url) do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
        "#{conn.scheme}://#{conn.host}#{port}"
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
