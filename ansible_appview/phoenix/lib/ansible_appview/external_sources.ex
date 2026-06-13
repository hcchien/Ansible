defmodule AnsibleAppview.ExternalSources do
  @moduledoc """
  Admin-managed curated allowlist of remote ActivityPub actors (inbound
  federation, design 2026-06-13).

  This is the only gate that decides whose public outbox the ingest poller pulls.
  It is intentionally admin-only: there is no public endpoint in this slice — a
  seed/config path plus these context functions are the whole management surface.

  Reversibility (Constitution Base Rule 7): `disable/1` and `remove/1` are the
  levers that make a source's content disappear from Elix. Disabling stops future
  polls; combined with the actor-keyed `feed_items.external_actor_uri` column, an
  operator can also drop already-ingested rows for a removed source.

  TODO(Task 4a/4b): the per-board `external_inclusion` policy (relay forum-host)
  and the per-user opt-in filter are where external items eventually become
  *visible*. This module only governs ingestion; it grants no read surface.
  """

  import Ecto.Query

  alias AnsibleAppview.Repo
  alias AnsibleAppview.Db.ExternalSource

  @doc "All curated sources, newest first."
  @spec list() :: [ExternalSource.t()]
  def list do
    Repo.all(from(s in ExternalSource, order_by: [desc: s.inserted_at]))
  end

  @doc "Enabled sources only — the set the poller pulls."
  @spec list_enabled() :: [ExternalSource.t()]
  def list_enabled do
    Repo.all(from(s in ExternalSource, where: s.enabled == true, order_by: [asc: s.id]))
  end

  @doc """
  Curated sources mapped to one Elix board (design D4, Task 4b-1), newest first.
  These are the sources whose external content surfaces in `board_id`'s external
  lane. Returns `[]` for a board with no mapped sources.
  """
  @spec list_for_board(String.t()) :: [ExternalSource.t()]
  def list_for_board(board_id) when is_binary(board_id) do
    Repo.all(
      from(s in ExternalSource,
        where: s.board_id == ^board_id,
        order_by: [desc: s.inserted_at]
      )
    )
  end

  @doc "Fetch by AP actor URI, or nil."
  @spec get_by_actor_uri(String.t()) :: ExternalSource.t() | nil
  def get_by_actor_uri(actor_uri), do: Repo.get_by(ExternalSource, actor_uri: actor_uri)

  @doc """
  Add (or update on conflict) a curated source. `attrs` must carry `:actor_uri`
  and `:instance`; `:compliance_level` defaults to `"unknown"`, `:enabled` to
  true, and `:board_id` (the Elix board this source surfaces in) is optional
  (NULL = not surfaced to any board). Idempotent on `actor_uri` so re-seeding is
  safe — `board_id` is updated on conflict so re-mapping a source is a re-add.
  """
  @spec add(map()) :: {:ok, ExternalSource.t()} | {:error, Ecto.Changeset.t()}
  def add(attrs) do
    attrs = normalize_attrs(attrs)

    %ExternalSource{}
    |> ExternalSource.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:instance, :display_name, :compliance_level, :enabled, :board_id, :updated_at]},
      conflict_target: :actor_uri,
      returning: true
    )
  end

  @doc "Disable a source by actor URI (stops future polls). Reversibility lever."
  @spec disable(String.t()) :: {:ok, ExternalSource.t()} | {:error, term()}
  def disable(actor_uri), do: set_enabled(actor_uri, false)

  @doc "Re-enable a previously disabled source."
  @spec enable(String.t()) :: {:ok, ExternalSource.t()} | {:error, term()}
  def enable(actor_uri), do: set_enabled(actor_uri, true)

  @doc "Remove a source from the allowlist entirely (the exit path)."
  @spec remove(String.t()) :: :ok
  def remove(actor_uri) do
    Repo.delete_all(from(s in ExternalSource, where: s.actor_uri == ^actor_uri))
    :ok
  end

  @doc "Record a successful poll time (best-effort; never raises)."
  @spec mark_polled(String.t()) :: :ok
  def mark_polled(actor_uri) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.update_all(from(s in ExternalSource, where: s.actor_uri == ^actor_uri),
      set: [last_polled_at: now]
    )

    :ok
  end

  @doc """
  Seed sources from config (`:external_sources` list of maps). Idempotent; safe
  to call on boot. Returns the count seeded.
  """
  @spec seed_from_config() :: non_neg_integer()
  def seed_from_config do
    Application.get_env(:ansible_appview, :external_sources, [])
    |> Enum.reduce(0, fn attrs, acc ->
      case add(attrs) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp set_enabled(actor_uri, value) do
    case get_by_actor_uri(actor_uri) do
      nil ->
        {:error, :not_found}

      source ->
        source
        |> ExternalSource.changeset(%{enabled: value})
        |> Repo.update()
    end
  end

  # Accept string- or atom-keyed maps from config/callers.
  defp normalize_attrs(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
    end)
  end
end
