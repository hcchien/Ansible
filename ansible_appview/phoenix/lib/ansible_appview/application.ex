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
        read_repo_children() ++
        cache_children() ++
        ingest_children() ++
        [
          {Bandit, plug: AnsibleAppview.Web.Router, port: port}
        ]

    opts = [strategy: :one_for_one, name: AnsibleAppview.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp read_repo_children do
    if Application.get_env(:ansible_appview, :start_read_repo, false) do
      [AnsibleAppview.ReadRepo]
    else
      []
    end
  end

  defp cache_children do
    redis =
      if Application.get_env(:ansible_appview, :start_redis, false) do
        [{Redix, {Application.fetch_env!(:ansible_appview, :redis_url), [name: :appview_redis]}}]
      else
        []
      end

    # The ETS adapter's table owner always runs (used as the local default and as
    # a safe fallback even when Redis is the active adapter).
    [AnsibleAppview.Cache.ETS] ++ redis
  end

  defp ingest_children do
    if Application.get_env(:ansible_appview, :start_ingest, true) do
      [AnsibleAppview.Ingest.Poller]
    else
      []
    end
  end
end
