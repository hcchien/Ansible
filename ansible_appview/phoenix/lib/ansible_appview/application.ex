defmodule AnsibleAppview.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:ansible_appview, :port, 4000)
    Logger.info("Starting Ansible AppView on port #{port}")

    children =
      [
        AnsibleAppview.Repo
      ] ++
        ingest_children() ++
        [
          {Bandit, plug: AnsibleAppview.Web.Router, port: port}
        ]

    opts = [strategy: :one_for_one, name: AnsibleAppview.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ingest_children do
    if Application.get_env(:ansible_appview, :start_ingest, true) do
      [AnsibleAppview.Ingest.Poller]
    else
      []
    end
  end
end
