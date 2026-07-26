defmodule AnsibleRelay.Web.RawBodyReader do
  @moduledoc """
  Plug.Parsers body reader that preserves the exact bytes needed for HTTP
  Digest and Signature verification.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        previous = conn.private[:raw_body] || ""
        {:ok, body, Plug.Conn.put_private(conn, :raw_body, previous <> body)}

      {:more, body, conn} ->
        previous = conn.private[:raw_body] || ""
        {:more, body, Plug.Conn.put_private(conn, :raw_body, previous <> body)}

      other ->
        other
    end
  end
end
