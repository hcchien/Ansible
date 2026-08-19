defmodule AnsibleRelay.Web.Controllers.IdentityMigrationController do
  import Plug.Conn

  alias AnsibleRelay.Identity.MigrationStore

  def submit(conn, params) do
    case MigrationStore.submit(params) do
      {:ok, migration} -> send_json(conn, 201, migration)
      {:error, :malformed} -> send_json(conn, 422, %{error: "malformed_migration"})
      {:error, :not_legacy} -> send_json(conn, 422, %{error: "not_legacy_did"})
      {:error, :not_v1} -> send_json(conn, 422, %{error: "not_v1_did"})
      {:error, :invalid_signature} -> send_json(conn, 401, %{error: "invalid_signature"})
      {:error, :did_not_found} -> send_json(conn, 404, %{error: "did_not_found"})
      {:error, :invalid_chain} -> send_json(conn, 409, %{error: "invalid_chain"})
      {:error, :conflict} -> send_json(conn, 409, %{error: "migration_conflict"})
      {:error, :locked} -> send_json(conn, 423, %{error: "account_frozen"})
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
