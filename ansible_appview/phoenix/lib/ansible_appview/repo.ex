defmodule AnsibleAppview.Repo do
  use Ecto.Repo,
    otp_app: :ansible_appview,
    adapter: Ecto.Adapters.Postgres
end
