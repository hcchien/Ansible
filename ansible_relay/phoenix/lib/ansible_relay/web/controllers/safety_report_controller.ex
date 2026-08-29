defmodule AnsibleRelay.Web.Controllers.SafetyReportController do
  import Plug.Conn

  alias AnsibleRelay.{SafetyReportIntent, SafetyReports}

  def create(conn, params) do
    case SafetyReportIntent.verify(params) do
      {:ok, attrs} ->
        send_result(conn, SafetyReports.create(attrs))

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, reason} when reason in [:invalid_signature, :missing_signature, :unknown_did] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, reason} ->
        send_json(conn, 422, %{error: Atom.to_string(reason)})
    end
  end

  defp send_result(conn, {:ok, :created, event}), do: send_json(conn, 201, %{event: event})
  defp send_result(conn, {:ok, :duplicate, event}), do: send_json(conn, 200, %{event: event})

  defp send_result(conn, {:error, reason}) when is_atom(reason),
    do: send_json(conn, 422, %{error: Atom.to_string(reason)})

  defp send_result(conn, {:error, _changeset}),
    do: send_json(conn, 422, %{error: "invalid_safety_event"})

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
