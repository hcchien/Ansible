defmodule AnsibleRelay.GossipsubTopic do
  @moduledoc """
  Gossipsub topic naming convention for CRDT Ops.

  Canonical format:

      /ansible/ops/v1/{network}/{scope}
  """

  @prefix "/ansible/ops/v1"
  @networks ~w(mainnet testnet devnet local)
  @scope_regex ~r/^[a-z0-9][a-z0-9-]{0,62}$/

  @type network :: String.t()
  @type scope :: String.t()
  @type reject_reason ::
          :invalid_topic_format
          | :unknown_network
          | :invalid_scope
          | :unsupported_topic_version

  @doc "Build a canonical Op topic."
  @spec build(network(), scope()) :: {:ok, String.t()} | {:error, reject_reason()}
  def build(network, scope) when is_binary(network) and is_binary(scope) do
    topic = "#{@prefix}/#{network}/#{scope}"

    case validate(topic) do
      :ok -> {:ok, topic}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Validate a Gossipsub Op topic."
  @spec validate(String.t()) :: :ok | {:error, reject_reason()}
  def validate(topic) when is_binary(topic) do
    case String.split(topic, "/", trim: true) do
      ["ansible", "ops", "v1", network, scope] ->
        cond do
          network not in @networks -> {:error, :unknown_network}
          not Regex.match?(@scope_regex, scope) -> {:error, :invalid_scope}
          true -> :ok
        end

      ["ansible", "ops", version | _] when version != "v1" ->
        {:error, :unsupported_topic_version}

      _ ->
        {:error, :invalid_topic_format}
    end
  end

  @doc "Return configured canonical mainnet topic."
  @spec mainnet_global() :: String.t()
  def mainnet_global, do: "#{@prefix}/mainnet/global"

  @doc "Return accepted network names."
  @spec networks() :: [String.t()]
  def networks, do: @networks
end
