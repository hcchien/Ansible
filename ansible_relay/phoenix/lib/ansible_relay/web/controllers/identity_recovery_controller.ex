defmodule AnsibleRelay.Web.Controllers.IdentityRecoveryController do
  import Plug.Conn

  alias AnsibleRelay.Identity.{AnchorStore, RecoveryStore}

  def configure_codes(conn, params) do
    case RecoveryStore.configure(params) do
      {:ok, status} -> send_json(conn, 201, status)
      {:error, :invalid_signature} -> send_json(conn, 401, %{error: "invalid_signature"})
      {:error, :malformed} -> send_json(conn, 422, %{error: "malformed_recovery_codes"})
      {:error, _} -> send_json(conn, 409, %{error: "recovery_codes_conflict"})
    end
  end

  def code_status(conn, %{"did" => did}) do
    send_json(conn, 200, RecoveryStore.status(did))
  end

  def recover_with_code(conn, params) do
    anchor = params["anchor"]
    code = params["recovery_code"]

    case recovery_rate_limit(conn, anchor) do
      :ok ->
        recover_with_code_result(conn, anchor, code)

      {:error, :rate_limited, detail} ->
        send_json(conn, 429, %{error: "rate_limited", detail: detail})
    end
  end

  defp recover_with_code_result(conn, anchor, code) do
    case RecoveryStore.recover(anchor, code) do
      {:ok, {:pending, row}} ->
        send_json(conn, 202, %{
          state: "pending",
          anchor_cid: row.anchor_cid,
          grace_until: DateTime.to_iso8601(row.grace_until)
        })

      {:error, :invalid_recovery_code} ->
        send_json(conn, 401, %{error: "invalid_recovery_code"})

      {:error, error} when error in [:invalid_signature, :invalid_attestation] ->
        send_json(conn, 401, %{error: Atom.to_string(error)})

      {:error, error} when error in [:conflict, :chain_mismatch, :locked] ->
        send_json(conn, if(error == :locked, do: 423, else: 409), %{
          error: Atom.to_string(error)
        })

      {:error, _} ->
        send_json(conn, 422, %{error: "malformed_recovery"})
    end
  end

  defp recovery_rate_limit(conn, anchor) do
    did = if is_map(anchor), do: anchor["did"], else: "unknown"
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    subject =
      :crypto.hash(:sha256, "recovery\0" <> to_string(did) <> "\0" <> ip)
      |> Base.encode16(case: :lower)

    AnsibleRelay.AbuseDetector.check_peer(subject)
  end

  def devices(conn, %{"did" => did}) do
    case AnchorStore.get_active(did) do
      {:ok, anchor} ->
        devices =
          Enum.map(anchor["devices"] || [], fn device ->
            Map.take(device, [
              "device_id",
              "device_key",
              "custody_class",
              "enrolled_at",
              "attestation_sig"
            ])
          end)

        send_json(conn, 200, %{
          did: did,
          anchor_cid: anchor["anchor_cid"],
          devices: devices
        })

      {:error, :locked} ->
        send_json(conn, 423, %{error: "account_frozen"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "anchor_not_found"})
    end
  end

  def audit(conn, %{"did" => did}) do
    send_json(conn, 200, %{did: did, events: RecoveryStore.audit(did)})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
