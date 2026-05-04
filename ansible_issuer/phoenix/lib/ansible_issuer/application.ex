defmodule AnsibleIssuer.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:ansible_issuer, :port, 4002)
    Logger.info("Starting Ansible Issuer on port #{port}")

    children = [
      AnsibleIssuer.OtpStore,
      {Bandit, plug: AnsibleIssuer.Web.Router, port: port}
    ]

    opts = [strategy: :one_for_one, name: AnsibleIssuer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
