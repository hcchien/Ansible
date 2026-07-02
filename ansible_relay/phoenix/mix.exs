defmodule AnsibleRelay.MixProject do
  use Mix.Project

  def project do
    [
      app: :ansible_relay,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :inets, :ssl],
      mod: {AnsibleRelay.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      # Persistence
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},
      # Rustler NIF for Ed25519
      {:rustler, "~> 0.31"},
      # Erlang clustering for multi-node deployments (off until a topology is set)
      {:libcluster, "~> 3.3"},
      # Optional shared (cross-instance) abuse limiter backend
      {:redix, "~> 1.2"},
    ]
  end
end
