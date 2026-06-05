defmodule AnsibleAppview.ReadRepo do
  @moduledoc """
  Read-only replica repo for timeline/board-feed queries. Only started and used
  when `DATABASE_REPLICA_URL` is configured (see runtime.exs); otherwise the
  timeline reads fall back to the primary `AnsibleAppview.Repo`. Keeping it out
  of `:ecto_repos` means migrations never target the replica.
  """
  use Ecto.Repo,
    otp_app: :ansible_appview,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
