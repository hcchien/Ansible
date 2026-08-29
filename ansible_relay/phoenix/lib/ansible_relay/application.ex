defmodule AnsibleRelay.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:ansible_relay, :port, 4000)
    Logger.info("Starting Ansible Relay on port #{port}")

    children =
      cluster_children() ++
        abuse_limiter_children() ++
        [
          AnsibleRelay.Repo,
          AnsibleRelay.Metrics,
          AnsibleRelay.IdentityCache,
          AnsibleRelay.DidAccountCache,
          AnsibleRelay.WebSessionStore,
          AnsibleRelay.MessengerStore,
          AnsibleRelay.AbuseDetector,
          AnsibleRelay.ForumHost.ReportRateLimiter,
          AnsibleRelay.CommunityNotes.RateLimiter,
          AnsibleRelay.OpStore,
          # Supervises the wake-push send tasks so a slow push endpoint can't
          # back up the WakeScheduler mailbox.
          {Task.Supervisor, name: AnsibleRelay.Push.WakeTaskSupervisor},
          AnsibleRelay.Push.WakeScheduler,
          # Drives outbound ActivityPub delivery. No-op unless
          # :activity_pub_delivery_enabled is true (default off); see the module.
          AnsibleRelay.ActivityPub.DeliveryPoller,
          {Bandit, plug: AnsibleRelay.Web.Router, port: port}
        ]

    opts = [strategy: :one_for_one, name: AnsibleRelay.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Starts Erlang clustering only when a topology is configured (multi-node /
  # GKE). Single-node (Cloud Run, dev, tests) has an empty topology and runs no
  # cluster supervisor; horizontal scaling there is via shared PostgreSQL.
  defp cluster_children do
    case Application.get_env(:libcluster, :topologies, []) do
      [] ->
        []

      topologies ->
        [{Cluster.Supervisor, [topologies, [name: AnsibleRelay.ClusterSupervisor]]}]
    end
  end

  # Starts the Redis connection only when a shared abuse limiter is configured.
  defp abuse_limiter_children do
    case Application.get_env(:ansible_relay, :abuse_limiter_redis_url) do
      nil -> []
      url -> [{Redix, {url, [name: :relay_redis]}}]
    end
  end
end
