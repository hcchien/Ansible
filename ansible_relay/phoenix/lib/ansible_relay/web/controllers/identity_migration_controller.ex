defmodule AnsibleRelay.Web.Controllers.IdentityMigrationController do
  import Plug.Conn

  alias AnsibleRelay.Identity.MigrationStore

  def submit(conn, params) do
    case MigrationStore.submit(params) do
      {:ok, :created, migration} ->
        send_json(conn, 201, migration)

      {:ok, :existing, migration} ->
        send_json(conn, 200, migration)

      {:error, :malformed} ->
        send_json(conn, 422, %{error: "malformed_migration"})

      {:error, :not_legacy} ->
        send_json(conn, 422, %{error: "not_legacy_did"})

      {:error, :not_v1} ->
        send_json(conn, 422, %{error: "not_v1_did"})

      {:error, :invalid_signature} ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :did_not_found} ->
        send_json(conn, 404, %{error: "did_not_found"})

      {:error, :invalid_chain} ->
        send_json(conn, 409, %{error: "invalid_chain"})

      {:error, :handle_mismatch} ->
        send_json(conn, 409, %{error: "handle_mismatch"})

      {:error, :account_not_found} ->
        send_json(conn, 409, %{error: "legacy_account_not_found"})

      {:error, :account_state_mismatch} ->
        send_json(conn, 409, %{error: "account_state_mismatch"})

      {:error, :conflict} ->
        send_json(conn, 409, %{error: "migration_conflict"})

      {:error, :locked} ->
        send_json(conn, 423, %{error: "account_frozen"})

      {:error, :unavailable} ->
        send_json(conn, 503, %{error: "migration_unavailable", retryable: true})
    end
  end

  def show(conn, %{"legacy_did" => legacy_did}) do
    case MigrationStore.get(legacy_did) do
      {:ok, migration} -> send_json(conn, 200, migration)
      {:error, :not_found} -> send_json(conn, 404, %{error: "migration_not_found"})
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
