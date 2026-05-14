defmodule AnsibleRelay.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:ansible_relay, :port, 4000)
    Logger.info("Starting Ansible Relay on port #{port}")

    children = [
      AnsibleRelay.Repo,
      AnsibleRelay.IdentityCache,
      AnsibleRelay.DidAccountCache,
      AnsibleRelay.WebSessionStore,
      AnsibleRelay.MessengerStore,
      AnsibleRelay.AbuseDetector,
      AnsibleRelay.OpStore,
      {Bandit, plug: AnsibleRelay.Web.Router, port: port}
    ]

    opts = [strategy: :one_for_one, name: AnsibleRelay.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
