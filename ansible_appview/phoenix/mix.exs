defmodule AnsibleAppview.MixProject do
  use Mix.Project

  def project do
    [
      app: :ansible_appview,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :inets, :ssl],
      mod: {AnsibleAppview.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},
      {:redix, "~> 1.2"}
    ]
  end
end
