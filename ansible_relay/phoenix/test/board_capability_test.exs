defmodule AnsibleRelay.ForumHost.BoardCapabilityTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Db.ForumHostBoard
  alias AnsibleRelay.ForumHost.BoardCapability
  alias AnsibleRelay.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "issues and authorizes a capability with the canonical board id" do
    hosted_key = "legacy-hosted-key-#{System.unique_integer([:positive])}"

    board =
      Repo.insert!(%ForumHostBoard{
        hosted_board_id: hosted_key,
        slug: hosted_key,
        canonical_board_uri: "https://relay.example/boards/#{hosted_key}",
        title: "Canonical capability test"
      })

    canonical_id = Integer.to_string(board.board_id)
    thumbprint = "device-thumbprint-canonical-test"

    assert {:ok, token, grant} =
             BoardCapability.issue(board, "did:elix:pairwise", thumbprint, ["post"])

    assert grant.hosted_board_id == hosted_key

    assert {:ok, _grant} =
             BoardCapability.authorize(token, canonical_id, "post", thumbprint)

    # Legacy routes resolve before DPoP/capability verification, so a queued
    # operation with the old hosted key cannot bypass or break the canonical
    # grant binding during migration.
    assert {:ok, _grant} = BoardCapability.authorize(token, hosted_key, "post", thumbprint)
  end
end
