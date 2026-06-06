defmodule AnsibleRelay.ForumHost.StoreTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.{ForumHost.Store, Repo}
  alias AnsibleRelay.Db.{ForumHostAcceptedIntent, ForumHostAnnouncement, ForumHostBoard}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    original_base_url = Application.get_env(:ansible_relay, :forum_host_base_url)
    original_seed_boards = Application.get_env(:ansible_relay, :forum_host_seed_boards)
    original_announcements = Application.get_env(:ansible_relay, :forum_host_announcements)
    original_posting_policy = Application.get_env(:ansible_relay, :forum_host_posting_policy)

    original_moderation_policy =
      Application.get_env(:ansible_relay, :forum_host_moderation_policy)

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
      restore_env(:forum_host_posting_policy, original_posting_policy)
      restore_env(:forum_host_moderation_policy, original_moderation_policy)
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

  test "search_boards matches title/description/tags and browses on empty query" do
    :ok = Store.ensure_seeded!()

    {:ok, _} =
      Store.create_board(%{
        intent_id: "intent-photo",
        author_did: "did:plc:a",
        title: "Photography",
        description: "Cameras and lenses",
        tags: ["art", "hobby"]
      })

    {:ok, _} =
      Store.create_board(%{
        intent_id: "intent-cook",
        author_did: "did:plc:b",
        title: "Cooking",
        description: "Recipes",
        tags: ["food"]
      })

    # Title substring (case-insensitive).
    assert Store.search_boards("photo", 20) |> Enum.map(& &1.title) == ["Photography"]
    # Description substring.
    assert Store.search_boards("recipes", 20) |> Enum.map(& &1.title) == ["Cooking"]
    # Tag match.
    assert Store.search_boards("hobby", 20) |> Enum.map(& &1.title) == ["Photography"]
    # Empty query browses all (seeded General + the two created), title-ordered.
    assert Store.search_boards("", 20) |> Enum.map(& &1.title) ==
             ["Cooking", "General", "Photography"]
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

    assert %ForumHostAcceptedIntent{
             author_did: "did:plc:author123",
             action: "create_board",
             result_kind: "forum_host_board",
             result_id: "reading-group",
             payload_hash: payload_hash
           } = Repo.get(ForumHostAcceptedIntent, "intent-123")

    assert String.length(payload_hash) == 64

    assert {:error, :duplicate_intent} =
             Store.create_board(%{
               intent_id: "intent-123",
               author_did: "did:plc:author123",
               title: "Another Title"
             })
  end

  test "create_board permits exact intent replay but rejects changed payload details" do
    :ok = Store.ensure_seeded!()

    payload = %{
      intent_id: "intent-full-payload",
      author_did: "did:plc:author456",
      title: "Policy Board",
      description: "Board with explicit policy",
      language: "en",
      tags: ["policy", "starter"],
      permissions: %{"read" => true, "write" => true},
      posting_policy: %{"min_trust_tier" => "verified_human"},
      moderation_policy: %{"appeals" => true, "reason_codes" => ["spam"]}
    }

    assert {:ok, board} = Store.create_board(payload)

    assert {:ok, replayed_board} = Store.create_board(payload)
    assert replayed_board.hosted_board_id == board.hosted_board_id

    assert {:error, :duplicate_intent} =
             Store.create_board(%{
               payload
               | tags: ["policy", "changed"],
                 posting_policy: %{"min_trust_tier" => "self_custody_did"}
             })
  end

  test "create_board replays omitted-policy payload after host defaults change" do
    :ok = Store.ensure_seeded!()

    payload = %{
      intent_id: "intent-default-independent",
      author_did: "did:plc:author789",
      title: "Defaults Replay",
      description: "Uses host defaults"
    }

    assert {:ok, board} = Store.create_board(payload)
    assert board.posting_policy == %{"min_trust_tier" => "self_custody_did"}

    Application.put_env(:ansible_relay, :forum_host_posting_policy, %{
      "min_trust_tier" => "verified_human"
    })

    Application.put_env(:ansible_relay, :forum_host_moderation_policy, %{
      "appeals" => false,
      "reason_codes" => ["spam"]
    })

    assert {:ok, replayed_board} = Store.create_board(payload)
    assert replayed_board.hosted_board_id == board.hosted_board_id
    assert replayed_board.posting_policy == %{"min_trust_tier" => "self_custody_did"}
  end

  test "create_board assigns deterministic slug suffixes for duplicate titles" do
    :ok = Store.ensure_seeded!()

    assert {:ok, first} =
             Store.create_board(%{
               intent_id: "intent-duplicate-title-1",
               author_did: "did:plc:author-title-1",
               title: "Shared Title"
             })

    assert {:ok, second} =
             Store.create_board(%{
               intent_id: "intent-duplicate-title-2",
               author_did: "did:plc:author-title-2",
               title: "Shared Title"
             })

    assert first.hosted_board_id == "shared-title"
    assert second.hosted_board_id == "shared-title-2"
    assert second.canonical_board_uri == "https://forum.trisaura.test/boards/shared-title-2"
  end

  test "create_board returns structured error for missing title" do
    assert {:error, {:invalid_board, [:title]}} =
             Store.create_board(%{
               intent_id: "intent-missing-title",
               author_did: "did:plc:author-missing-title"
             })
  end

  test "ensure_seeded! raises on invalid configured board" do
    Application.put_env(:ansible_relay, :forum_host_seed_boards, [
      %{
        "hosted_board_id" => "invalid",
        "slug" => "invalid",
        "description" => "Missing required title"
      }
    ])

    assert_raise Ecto.InvalidChangesetError, fn ->
      Store.ensure_seeded!()
    end
  end

  test "ensure_seeded! raises on invalid configured announcement" do
    Application.put_env(:ansible_relay, :forum_host_seed_boards, [])

    Application.put_env(:ansible_relay, :forum_host_announcements, [
      %{
        "announcement_id" => "invalid-announcement",
        "owner_kind" => "forum_host",
        "body" => "Missing required title",
        "severity" => "info"
      }
    ])

    assert_raise Ecto.InvalidChangesetError, fn ->
      Store.ensure_seeded!()
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
