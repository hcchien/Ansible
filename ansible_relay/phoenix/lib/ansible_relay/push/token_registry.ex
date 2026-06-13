defmodule AnsibleRelay.Push.TokenRegistry do
  @moduledoc """
  Registry of opaque per-device push tokens bound to a DID.

  Upserts are keyed by (subject_did, device_id) so a rotated token replaces
  the previous one. Unregistering deletes the row — the relay keeps no
  tombstone, so a deleted device can never be woken again (a mandatory
  property per the notification plan's constitution review).
  """

  import Ecto.Query

  alias AnsibleRelay.Db.DevicePushToken
  alias AnsibleRelay.Repo

  @doc """
  Upsert a token row by (subject_did, device_id).

  Returns `{:ok, :created}` for a new row, `{:ok, :updated}` when an
  existing registration was replaced.
  """
  def register(%{subject_did: subject_did, device_id: device_id} = attrs) do
    outcome = if exists?(subject_did, device_id), do: :updated, else: :created
    now = DateTime.utc_now()

    %DevicePushToken{}
    |> DevicePushToken.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          push_token: attrs.push_token,
          platform: attrs.platform,
          categories: attrs.categories,
          updated_at: now
        ]
      ],
      conflict_target: [:subject_did, :device_id]
    )
    |> case do
      {:ok, _row} -> {:ok, outcome}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Delete the token row for (subject_did, device_id). Idempotent."
  def unregister(subject_did, device_id) do
    {deleted, _} =
      Repo.delete_all(
        from(t in DevicePushToken,
          where: t.subject_did == ^subject_did and t.device_id == ^device_id
        )
      )

    {:ok, deleted}
  end

  @doc "All registered devices for a DID that opted into the given category."
  def devices_for(subject_did, category) do
    Repo.all(
      from(t in DevicePushToken,
        where: t.subject_did == ^subject_did and ^category in t.categories
      )
    )
  end

  @doc "Current registration for (subject_did, device_id), or nil."
  def lookup(subject_did, device_id) do
    Repo.get_by(DevicePushToken, subject_did: subject_did, device_id: device_id)
  end

  @doc false
  def reset do
    Repo.delete_all(DevicePushToken)
    :ok
  end

  defp exists?(subject_did, device_id) do
    Repo.exists?(
      from(t in DevicePushToken,
        where: t.subject_did == ^subject_did and t.device_id == ^device_id
      )
    )
  end
end
