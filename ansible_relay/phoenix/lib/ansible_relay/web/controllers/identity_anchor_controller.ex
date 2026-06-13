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

  alias AnsibleRelay.Identity.AnchorStore

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

      {:error, :invalid_signature} ->
        send_json(conn, 401, %{error: "invalid_signature"})

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

  # GET /api/v1/identity/anchor/:did
  def show(conn, %{"did" => did}) do
    case AnchorStore.get_active(did) do
      {:ok, object} ->
        send_json(conn, 200, object)

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "anchor_not_found"})

      {:error, :locked} ->
        send_json(conn, 423, %{error: "account_frozen"})
    end
  end

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

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
