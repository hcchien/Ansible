defmodule AnsibleAppview.Web.Controllers.ContextNotesController do
  @moduledoc "Public read API for signature-verified Community Notes."

  import Plug.Conn
  alias AnsibleAppview.ContextNotes

  def index(conn, params) do
    case params["target_ref"] do
      target_ref when is_binary(target_ref) and target_ref != "" ->
        send_json(conn, 200, %{
          target: ContextNotes.target_snapshot(target_ref),
          notes: ContextNotes.for_target(target_ref, parse_limit(params["limit"]))
        })

      _ ->
        send_json(conn, 422, %{error: "target_ref_required"})
    end
  end

  defp parse_limit(value) when is_integer(value), do: value

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> 20
    end
  end

  defp parse_limit(_), do: 20

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
