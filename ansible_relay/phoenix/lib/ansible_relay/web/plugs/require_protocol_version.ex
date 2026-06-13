defmodule AnsibleRelay.Web.Plugs.RequireProtocolVersion do
  @moduledoc """
  Enforces the relay's minimum supported protocol version on `/api/*` routes.

  Contract (service architecture plan, Phase 0 — API versioning):

    * Missing header — allowed (legacy grace period, logged at debug).
    * Unparseable header — allowed, treated like a legacy client.
    * Version < min supported — `426 upgrade_required` with the supported
      range so the client can show a clear "please update" message.
    * Version > current — allowed; newer clients are forward-compatible by
      design.
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  alias AnsibleRelay.Protocol

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/api/" <> _rest} = conn, _opts) do
    case get_req_header(conn, Protocol.header()) do
      [] ->
        Logger.debug(
          "#{Protocol.header()} header missing; allowing legacy client (#{conn.request_path})"
        )

        conn

      [raw | _rest] ->
        enforce(conn, raw)
    end
  end

  def call(conn, _opts), do: conn

  defp enforce(conn, raw) do
    case Integer.parse(String.trim(raw)) do
      {version, ""} ->
        if version < Protocol.min_supported_version() do
          upgrade_required(conn)
        else
          conn
        end

      _other ->
        Logger.debug(
          "unparseable #{Protocol.header()} header #{inspect(raw)}; allowing as legacy client"
        )

        conn
    end
  end

  defp upgrade_required(conn) do
    body =
      Jason.encode!(%{
        error: "upgrade_required",
        min_supported: Protocol.min_supported_version(),
        current: Protocol.current_version()
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(426, body)
    |> halt()
  end
end
