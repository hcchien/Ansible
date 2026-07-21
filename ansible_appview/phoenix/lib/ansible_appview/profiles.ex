defmodule AnsibleAppview.Profiles do
  @moduledoc """
  Actor profiles projected from public `profile` ops — the directory that makes
  people findable. Only public profile fields are ever stored (handle, display
  name, bio, avatar); no private metadata leaves the firehose.
  """

  import Ecto.Query

  alias AnsibleAppview.Repo
  alias AnsibleAppview.Db.Profile

  defp read_repo, do: Application.get_env(:ansible_appview, :read_repo, Repo)

  @doc "Upserts a profile from a folded op. Last write (highest log_id) wins."
  def upsert(did, attrs, log_id) do
    row =
      attrs
      |> Map.take([:handle, :display_name, :bio, :avatar_url, :author_tier])
      |> Map.put(:did, did)
      |> Map.put(:updated_log_id, log_id)

    Repo.insert(
      struct(Profile, row),
      on_conflict:
        {:replace, [:handle, :display_name, :bio, :avatar_url, :author_tier, :updated_log_id, :updated_at]},
      conflict_target: :did
    )
  end

  def get(did), do: read_repo().get(Profile, did)

  @doc "Lists the most recently published public profiles for discovery."
  def recent(limit \\ 20) do
    limit = limit |> min(100) |> max(1)

    read_repo().all(
      from p in Profile,
        order_by: [desc: p.updated_log_id],
        limit: ^limit
    )
    |> Enum.map(&to_map/1)
  end

  @doc """
  Prefix/substring search over handle and display name (case-insensitive). Ranks
  exact-handle and handle-prefix matches above display-name matches.
  """
  def search(query, limit \\ 20) when is_binary(query) do
    q = query |> String.trim() |> String.downcase()
    limit = limit |> min(50) |> max(1)

    if q == "" do
      []
    else
      like = escape_like(q) <> "%"
      contains = "%" <> escape_like(q) <> "%"

      read_repo().all(
        from p in Profile,
          where:
            like(fragment("lower(?)", p.handle), ^contains) or
              like(fragment("lower(?)", p.display_name), ^contains),
          order_by: [
            asc:
              fragment(
                "CASE WHEN lower(?) = ? THEN 0 WHEN lower(?) LIKE ? THEN 1 ELSE 2 END",
                p.handle,
                ^q,
                p.handle,
                ^like
              )
          ],
          limit: ^limit
      )
      |> Enum.map(&to_map/1)
    end
  end

  @doc false
  def to_map(%Profile{} = p) do
    %{
      did: p.did,
      handle: p.handle,
      display_name: p.display_name,
      bio: p.bio,
      avatar_url: p.avatar_url,
      reputation_tier: p.author_tier
    }
  end

  # Escape LIKE wildcards in user input so a literal % or _ can't widen the match.
  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
