defmodule AnsibleRelay.Repo do
  use Ecto.Repo,
    otp_app: :ansible_relay,
    adapter: Ecto.Adapters.Postgres
end
