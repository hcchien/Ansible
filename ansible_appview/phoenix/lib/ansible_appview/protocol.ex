defmodule AnsibleAppview.Protocol do
  @moduledoc """
  App↔AppView protocol version constants (service architecture plan, Phase 0).

  Clients advertise the protocol version they speak via the
  `x-ansible-protocol` request header; the AppView advertises its current and
  minimum supported versions in `GET /api/v1/meta`. Mirrors
  `AnsibleRelay.Protocol`.
  """

  @current_version 1
  @min_supported_version 1
  @header "x-ansible-protocol"

  @doc "Highest protocol version this AppView speaks."
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
