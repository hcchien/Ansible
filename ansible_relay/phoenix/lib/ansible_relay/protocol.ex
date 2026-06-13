defmodule AnsibleRelay.Protocol do
  @moduledoc """
  App↔relay protocol version constants (service architecture plan, Phase 0).

  Clients advertise the protocol version they speak via the
  `x-ansible-protocol` request header; the relay advertises both its current
  and minimum supported versions in `GET /api/v1/meta`. Op payloads carry an
  independent `schema_version` (also capped by `current_version/0`) so the op
  format can evolve additively without breaking long-tail clients.
  """

  @current_version 1
  @min_supported_version 1
  @header "x-ansible-protocol"

  @doc "Highest protocol version this relay speaks."
  def current_version, do: @current_version

  @doc "Oldest client protocol version still accepted."
  def min_supported_version, do: @min_supported_version

  @doc "Request header carrying the client's protocol version."
  def header, do: @header

  @doc "Version block advertised in meta/discovery responses."
  def advertisement do
    %{current: @current_version, min_supported: @min_supported_version}
  end
end
