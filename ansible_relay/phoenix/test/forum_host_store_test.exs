defmodule AnsibleRelay.ForumHost.StoreTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.{ForumHost.Store, Repo}
  alias AnsibleRelay.Db.{ForumHostAnnouncement, ForumHostBoard}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    original_base_url = Application.get_env(:ansible_relay, :forum_host_base_url)
    original_seed_boards = Application.get_env(:ansible_relay, :forum_host_seed_boards)
    original_announcements = Application.get_env(:ansible_relay, :forum_host_announcements)

    Application.put_env(:ansible_relay, :forum_host_base_url, "https://forum.trisaura.test")

    Application.put_env(:ansible_relay, :forum_host_seed_boards, [
      %{
        "hosted_board_id" => "general",
        "slug" => "general",
        "title" => "General",
        "description" => "General discussion",
        "language" => "en",
        "tags" => ["starter"],
        "permissions" => %{"read" => true, "write" => true},
        "posting_policy" => %{"min_trust_tier" => "self_custody_did"},
        "moderation_policy" => %{"appeals" => true}
      }
    ])

    Application.put_env(:ansible_relay, :forum_host_announcements, [
      %{
        "announcement_id" => "relay-maintenance",
        "owner_kind" => "forum_host",
        "title" => "Maintenance",
        "body" => "Posting may be delayed.",
        "severity" => "info",
        "locale" => "en"
      }
    ])

    on_exit(fn ->
      restore_env(:forum_host_base_url, original_base_url)
      restore_env(:forum_host_seed_boards, original_seed_boards)
      restore_env(:forum_host_announcements, original_announcements)
    end)

    :ok
  end

  test "ensure_seeded! creates durable configured boards and announcements" do
    assert Repo.aggregate(ForumHostBoard, :count) == 0
    assert Repo.aggregate(ForumHostAnnouncement, :count) == 0

    :ok = Store.ensure_seeded!()

    assert [%{hosted_board_id: "general"} = board] = Store.list_boards()
    assert board.canonical_board_uri == "https://forum.trisaura.test/boards/general"
    assert board.permissions == %{"read" => true, "write" => true}
    assert board.posting_policy == %{"min_trust_tier" => "self_custody_did"}
    assert board.moderation_policy == %{"appeals" => true}

    assert [%{announcement_id: "relay-maintenance"} = announcement] =
             Store.list_announcements()

    assert announcement.owner_kind == "forum_host"
    assert announcement.severity == "info"
  end

  test "create_board assigns host-owned identity and records accepted intent" do
    :ok = Store.ensure_seeded!()

    assert {:ok, board} =
             Store.create_board(%{
               intent_id: "intent-123",
               author_did: "did:plc:author123",
               title: "Reading Group",
               description: "Weekly discussion"
             })

    assert board.hosted_board_id == "reading-group"
    assert board.canonical_board_uri == "https://forum.trisaura.test/boards/reading-group"

    assert {:error, :duplicate_intent} =
             Store.create_board(%{
               intent_id: "intent-123",
               author_did: "did:plc:author123",
               title: "Another Title"
             })
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
