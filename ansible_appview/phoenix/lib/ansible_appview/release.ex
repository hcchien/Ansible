defmodule AnsibleAppview.Release do
  @moduledoc """
  Database tasks for the compiled OTP release (no `mix` at runtime).

      bin/ansible_appview eval "AnsibleAppview.Release.migrate()"
      bin/ansible_appview eval "AnsibleAppview.Release.rebuild()"
  """

  @app :ansible_appview

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

  @doc """
  Rebuilds the projection from scratch: truncates feed_items + ingest cursor and
  re-folds the relay op stream from the beginning. The projection is an
  acceleration artifact, so this reproduces the same state as incremental ingest.
  """
  def rebuild do
    load_app()
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, cache} = AnsibleAppview.Cache.ETS.start_link()
    {:ok, home_timeline} = AnsibleAppview.HomeTimeline.ETS.start_link()

    try do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(AnsibleAppview.Repo, fn _repo ->
          AnsibleAppview.Ingest.Rebuilder.run()
        end)
    after
      GenServer.stop(cache)
      GenServer.stop(home_timeline)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
