defmodule AnsibleRelay.Release do
  @moduledoc """
  Database migration tasks for the compiled OTP release.

  The production image is built with `mix release`, so `mix ecto.migrate` is not
  available at runtime. Run migrations against a deployed release with:

      bin/ansible_relay eval "AnsibleRelay.Release.migrate()"

  And roll a single repo back to a specific version with:

      bin/ansible_relay eval "AnsibleRelay.Release.rollback(AnsibleRelay.Repo, 20260101000001)"

  `with_repo/2` starts the repo (and only the repo) for the duration of the
  task, so these can run as a one-off Cloud Run Job or pre-start step without
  booting the full application supervision tree.
  """

  @app :ansible_relay

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
