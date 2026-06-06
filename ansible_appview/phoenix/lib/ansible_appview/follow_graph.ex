defmodule AnsibleAppview.FollowGraph do
  @moduledoc """
  Federated follow graph indexed from `follow` ops. Source of truth for fan-out
  (who follows an author) and for the read-time fallback (who a reader follows).
  Only federated follows are indexed; localOnly follows never leave the device.
  """

  import Ecto.Query
  alias AnsibleAppview.Repo
  alias AnsibleAppview.Db.Follow

  def upsert(follower_did, author_did, created_log_id) do
    Repo.insert(
      %Follow{
        follower_did: follower_did,
        author_did: author_did,
        created_log_id: created_log_id
      },
      on_conflict: {:replace, [:created_log_id]},
      conflict_target: [:follower_did, :author_did]
    )
  end

  def remove(follower_did, author_did) do
    Repo.delete_all(
      from(f in Follow,
        where: f.follower_did == ^follower_did and f.author_did == ^author_did
      )
    )

    :ok
  end

  @doc "DIDs that follow `author_did` (fan-out targets)."
  def followers(author_did) do
    Repo.all(from f in Follow, where: f.author_did == ^author_did, select: f.follower_did)
  end

  @doc "DIDs that `reader_did` follows (read fallback / rebuild)."
  def following(reader_did) do
    Repo.all(from f in Follow, where: f.follower_did == ^reader_did, select: f.author_did)
  end

  def follower_count(author_did) do
    Repo.aggregate(from(f in Follow, where: f.author_did == ^author_did), :count, :follower_did)
  end
end
