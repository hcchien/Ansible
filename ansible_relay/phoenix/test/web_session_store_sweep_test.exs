defmodule AnsibleRelay.WebSessionStoreSweepTest do
  @moduledoc "Periodic pruning of expired challenges and expired/revoked sessions."

  use ExUnit.Case, async: false

  alias AnsibleRelay.WebSessionStore

  setup do
    case WebSessionStore.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok = WebSessionStore.reset()
    :ok
  end

  test "sweep prunes an expired challenge but keeps an active one" do
    # Long-lived, stays after sweep.
    {:ok, active} = WebSessionStore.issue_challenge(%{"ttl_seconds" => 3600})
    # Already expired well beyond the retention grace.
    {:ok, stale} = WebSessionStore.issue_challenge(%{"ttl_seconds" => -7200})

    :ok = WebSessionStore.sweep_now()

    assert {:ok, _} = WebSessionStore.get_challenge(active.challenge_id)
    assert {:error, :not_found} = WebSessionStore.get_challenge(stale.challenge_id)
  end

  test "sweep prunes an expired session but keeps an active one" do
    active = approve_session(ttl_seconds: 3600)
    expired = approve_session(ttl_seconds: -7200)

    :ok = WebSessionStore.sweep_now()

    assert {:ok, _} = WebSessionStore.get_session(active.session_token)
    assert {:error, :not_found} = WebSessionStore.get_session(expired.session_token)
  end

  # Issue a challenge and approve it into a session with the given absolute TTL.
  defp approve_session(ttl_seconds: ttl) do
    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{"ttl_seconds" => 300, "scopes" => ["read"]})

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(ttl, :second)
      |> DateTime.to_iso8601()

    {:ok, session} =
      WebSessionStore.approve_challenge(challenge.challenge_id, %{
        expires_at: expires_at,
        approving_device_id: "dev-#{System.unique_integer([:positive])}",
        subject_did: "did:test:sweep#{System.unique_integer([:positive])}",
        scopes: ["read"]
      })

    session
  end
end
