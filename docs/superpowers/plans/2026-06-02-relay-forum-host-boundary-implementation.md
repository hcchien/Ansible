# Relay Forum Host Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the co-located Relay / Forum Host contract from the boundary spec so discovery, storage ownership, and write authorization are explicit and testable.

**Architecture:** Keep the current Phoenix service as the first deployment host, but split Relay and Forum Host responsibilities into separate controllers, stores, schemas, and auth paths. Forum Host discovery becomes durable and exposes compliance/identity/policy metadata; Relay discovery becomes the app bootstrap catalog; Forum Host writes accept either app DID signed intents or scoped web sessions with host audience.

**Tech Stack:** Elixir/Phoenix Plug, Ecto/Postgres, ExUnit/Plug.Test, Dart/Flutter, `package:http`, Node test runner scripts for the distribution frontend.

---

## Constitution Review

This plan implements behavior touching identity, storage, sync, verification,
Relay, Forum Host, AppView, moderation, and community governance. It follows
`docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`.

- Forum Host write paths verify either user DID signatures or scoped web
  sessions; neither path exposes user private keys.
- Discovery and write payloads carry only DID, scope, host audience, board
  target, trust tier, policy, and signature/session proof.
- Raw legal identity fields, provider assertions, biometric data, private keys,
  and personhood commitments are excluded from payloads and tests assert that.
- Forum Host moderation and rate-limit outputs remain host-level and
  reason-coded.
- External host compliance is represented by `constitution_compliance`, with
  unknown hosts defaulting to `unknown`.
- This implementation does not create a new personhood binding.

## Scope Check

The design spec covers several subsystems. This plan implements the first
co-located contract slice:

- Relay discovery endpoint and client contract.
- Forum Host durable discovery and announcements.
- Forum Host app signed-intent write auth.
- Forum Host web-session audience/cookie auth alignment.
- App and distribution frontend client contract updates.

This plan does not split Cloud Run services. The code must be structured so that
the later service split is a deployment change, not an API redesign.

## Current Implementation Status

As of 2026-06-02, Tasks 1-9 in this plan have been implemented and reviewed in
the current branch. The historical task bodies below still preserve their
test-first expected-failure wording, but the current code now includes:

- durable Forum Host discovery fields and seeded hosted boards;
- `GET /api/v1/discovery` for Relay bootstrap announcements, featured Forum
  Hosts, starter boards, cache/version metadata, and compliance labels;
- app DID signed create-board intents with `target_forum_host`;
- scoped web sessions with host audience and httpOnly cookie transport;
- CORS credential headers for allowed web origins;
- app clients for Relay discovery and signed Forum Host writes;
- distribution frontend public reads with `credentials: "omit"`;
- distribution frontend authenticated web-session/write calls with
  `credentials: "same-origin"`;
- app first-run discovery UI that displays announcements/starter boards and
  compliance without auto-subscribing, auto-posting, or creating local boards.

The final web transport fix is important: challenge creation remains
unauthenticated, but challenge polling uses same-origin credentials so the
browser accepts the relay's approved `Set-Cookie` response.

## File Structure

Create:

- `ansible_relay/phoenix/priv/repo/migrations/20260602000001_create_forum_host_tables.exs`
  - Creates Forum Host-owned tables for boards, announcements, and accepted
    write intents.
- `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_board.ex`
  - Ecto schema for durable hosted boards.
- `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_announcement.ex`
  - Ecto schema for Relay/Forum Host announcements stored by owner.
- `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_accepted_intent.ex`
  - Ecto schema for accepted signed intent idempotency.
- `ansible_relay/phoenix/lib/ansible_relay/forum_host/store.ex`
  - Forum Host store API for host metadata, seeded boards, announcements,
    create-board, and accepted intents.
- `ansible_relay/phoenix/lib/ansible_relay/forum_host/signed_intent.ex`
  - Canonical JSON and DID signature verification for app-originated Forum Host
    write intents.
- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/relay_discovery_controller.ex`
  - Elix Relay app bootstrap discovery endpoint.
- `ansible_relay/phoenix/test/forum_host_store_test.exs`
  - Store-level tests for durable seeded boards and announcements.
- `ansible_relay/phoenix/test/relay_discovery_controller_test.exs`
  - Relay discovery route tests.
- `ansible_node/app/lib/services/relay_discovery_client.dart`
  - App client for `GET /api/v1/discovery`.
- `ansible_node/app/test/relay_discovery_client_test.dart`
  - App discovery client tests.

Modify:

- `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
  - Add `GET /api/v1/discovery` and `GET /api/v1/forum-host/announcements`.
- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`
  - Return durable discovery metadata and split signed-intent vs web-session
    auth.
- `ansible_relay/phoenix/lib/ansible_relay/web/plugs/verify_web_session.ex`
  - Accept bearer or httpOnly session cookie and enforce optional audience.
- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex`
  - Include web session audience in challenges, grants, sessions, and responses.
- `ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`
  - Store audience on sessions.
- `ansible_relay/phoenix/test/forum_host_controller_test.exs`
  - Add discovery metadata, signed-intent auth, and rejection tests.
- `ansible_relay/phoenix/test/verify_web_session_test.exs`
  - Add cookie and audience tests.
- `ansible_relay/phoenix/test/web_session_controller_test.exs`
  - Add challenge/grant audience tests.
- `ansible_node/app/lib/services/forum_host_client.dart`
  - Add canonical signed create-board intent payload fields.
- `ansible_node/app/lib/services/web_session_grant_service.dart`
  - Add optional audience to app-approved web-session grants.
- `ansible_node/app/lib/services/web_session_approval_client.dart`
  - Parse audience from challenge/session responses.
- `ansible_node/app/lib/screens/web_session_approval_screen.dart`
  - Show target Forum Host audience when present.
- `ansible_node/app/lib/screens/home_shell.dart`
  - Sign canonical create-board intent payload instead of ad-hoc string.
- `ansible_node/app/test/forum_host_client_test.dart`
  - Verify canonical signed create-board payload.
- `ansible_node/app/test/web_session_grant_service_test.dart`
  - Verify canonical grant includes audience.
- `ansible_node/app/test/web_session_approval_client_test.dart`
  - Verify audience parsing.
- `ansible_node/app/test/web_session_approval_screen_test.dart`
  - Verify audience display.
- `ansible_distribution_frontend/src/relay_api_client.mjs`
  - Keep cookie-based auth and ensure requests send credentials consistently.
- `ansible_distribution_frontend/src/forum_host_client.mjs`
  - Keep web writes cookie-authenticated and public reads unauthenticated.
- `ansible_distribution_frontend/test/forum_host_client.test.mjs`
  - Verify write requests use cookies and no legacy bearer storage.
- `ansible_distribution_frontend/test/relay_api_client.test.mjs`
  - Verify request credentials behavior.

## Task 1: Durable Forum Host Store

**Files:**
- Create: `ansible_relay/phoenix/priv/repo/migrations/20260602000001_create_forum_host_tables.exs`
- Create: `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_board.ex`
- Create: `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_announcement.ex`
- Create: `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_accepted_intent.ex`
- Create: `ansible_relay/phoenix/lib/ansible_relay/forum_host/store.ex`
- Test: `ansible_relay/phoenix/test/forum_host_store_test.exs`

- [ ] **Step 1: Write failing store tests**

Create `ansible_relay/phoenix/test/forum_host_store_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run store tests and verify they fail**

Run:

```bash
cd ansible_relay/phoenix
mix test test/forum_host_store_test.exs
```

Expected: compile failure because `AnsibleRelay.ForumHost.Store` and schema
modules do not exist.

- [ ] **Step 3: Add migration**

Create `ansible_relay/phoenix/priv/repo/migrations/20260602000001_create_forum_host_tables.exs`:

```elixir
defmodule AnsibleRelay.Repo.Migrations.CreateForumHostTables do
  use Ecto.Migration

  def change do
    create table(:forum_host_boards, primary_key: false) do
      add :hosted_board_id, :string, primary_key: true
      add :slug, :string, null: false
      add :canonical_board_uri, :string, null: false
      add :title, :string, null: false
      add :description, :text
      add :language, :string
      add :tags, {:array, :string}, null: false, default: []
      add :permissions, :map, null: false, default: %{}
      add :posting_policy, :map, null: false, default: %{}
      add :moderation_policy, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:forum_host_boards, [:slug])
    create unique_index(:forum_host_boards, [:canonical_board_uri])

    create table(:forum_host_announcements, primary_key: false) do
      add :announcement_id, :string, primary_key: true
      add :owner_kind, :string, null: false
      add :hosted_board_id, references(:forum_host_boards,
        column: :hosted_board_id,
        type: :string,
        on_delete: :nilify_all
      )
      add :title, :string, null: false
      add :body, :text, null: false
      add :severity, :string, null: false, default: "info"
      add :locale, :string
      add :url, :string
      add :starts_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:forum_host_announcements, [:owner_kind])
    create index(:forum_host_announcements, [:hosted_board_id])

    create table(:forum_host_accepted_intents, primary_key: false) do
      add :intent_id, :string, primary_key: true
      add :author_did, :string, null: false
      add :action, :string, null: false
      add :payload_hash, :string, null: false
      add :result_kind, :string, null: false
      add :result_id, :string, null: false
      add :accepted_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:forum_host_accepted_intents, [:author_did])
    create index(:forum_host_accepted_intents, [:result_kind, :result_id])
  end
end
```

- [ ] **Step 4: Add schema modules**

Create `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_board.ex`:

```elixir
defmodule AnsibleRelay.Db.ForumHostBoard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:hosted_board_id, :string, autogenerate: false}
  @derive {Jason.Encoder,
           only: [
             :hosted_board_id,
             :slug,
             :canonical_board_uri,
             :title,
             :description,
             :language,
             :tags,
             :permissions,
             :posting_policy,
             :moderation_policy
           ]}
  schema "forum_host_boards" do
    field :slug, :string
    field :canonical_board_uri, :string
    field :title, :string
    field :description, :string
    field :language, :string
    field :tags, {:array, :string}, default: []
    field :permissions, :map, default: %{}
    field :posting_policy, :map, default: %{}
    field :moderation_policy, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(board, attrs) do
    board
    |> cast(attrs, [
      :hosted_board_id,
      :slug,
      :canonical_board_uri,
      :title,
      :description,
      :language,
      :tags,
      :permissions,
      :posting_policy,
      :moderation_policy
    ])
    |> validate_required([:hosted_board_id, :slug, :canonical_board_uri, :title])
    |> unique_constraint(:slug)
    |> unique_constraint(:canonical_board_uri)
  end
end
```

Create `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_announcement.ex`:

```elixir
defmodule AnsibleRelay.Db.ForumHostAnnouncement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:announcement_id, :string, autogenerate: false}
  @derive {Jason.Encoder,
           only: [
             :announcement_id,
             :owner_kind,
             :hosted_board_id,
             :title,
             :body,
             :severity,
             :locale,
             :url,
             :starts_at,
             :expires_at
           ]}
  schema "forum_host_announcements" do
    field :owner_kind, :string
    field :hosted_board_id, :string
    field :title, :string
    field :body, :string
    field :severity, :string, default: "info"
    field :locale, :string
    field :url, :string
    field :starts_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(announcement, attrs) do
    announcement
    |> cast(attrs, [
      :announcement_id,
      :owner_kind,
      :hosted_board_id,
      :title,
      :body,
      :severity,
      :locale,
      :url,
      :starts_at,
      :expires_at
    ])
    |> validate_required([:announcement_id, :owner_kind, :title, :body, :severity])
    |> validate_inclusion(:owner_kind, ["relay", "forum_host", "board"])
    |> validate_inclusion(:severity, ["info", "warning", "critical"])
  end
end
```

Create `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_accepted_intent.ex`:

```elixir
defmodule AnsibleRelay.Db.ForumHostAcceptedIntent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:intent_id, :string, autogenerate: false}
  schema "forum_host_accepted_intents" do
    field :author_did, :string
    field :action, :string
    field :payload_hash, :string
    field :result_kind, :string
    field :result_id, :string
    field :accepted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(intent, attrs) do
    intent
    |> cast(attrs, [
      :intent_id,
      :author_did,
      :action,
      :payload_hash,
      :result_kind,
      :result_id,
      :accepted_at
    ])
    |> validate_required([
      :intent_id,
      :author_did,
      :action,
      :payload_hash,
      :result_kind,
      :result_id,
      :accepted_at
    ])
  end
end
```

- [ ] **Step 5: Add Forum Host store**

Create `ansible_relay/phoenix/lib/ansible_relay/forum_host/store.ex`:

```elixir
defmodule AnsibleRelay.ForumHost.Store do
  @moduledoc "Durable co-located Forum Host storage and metadata helpers."

  import Ecto.Query

  alias AnsibleRelay.Repo
  alias AnsibleRelay.Db.{ForumHostAcceptedIntent, ForumHostAnnouncement, ForumHostBoard}

  @default_base_url "http://localhost:4001"

  def ensure_seeded! do
    Enum.each(seed_boards(), &upsert_seed_board/1)
    Enum.each(seed_announcements(), &upsert_seed_announcement/1)
    :ok
  end

  def host_info do
    %{
      forum_host_id: forum_host_id(),
      display_name: display_name(),
      canonical_base_url: base_url(),
      base_url: base_url(),
      canonical_host_uri: base_url(),
      server_kind: "ansibleForumHost",
      constitution_compliance: constitution_compliance(),
      host_public_keys: host_public_keys(),
      accepted_session_issuers: accepted_session_issuers(),
      rules: rules(),
      moderation_policy: moderation_policy(),
      posting_policy: posting_policy(),
      capabilities: %{
        create_boards: true,
        create_threads: true,
        cross_post: true,
        announcements: true
      }
    }
  end

  def list_boards do
    ensure_seeded!()

    ForumHostBoard
    |> order_by([board], asc: board.title)
    |> Repo.all()
  end

  def list_announcements(owner_kind \\ nil) do
    ensure_seeded!()
    now = DateTime.utc_now()

    ForumHostAnnouncement
    |> where([announcement], is_nil(announcement.starts_at) or announcement.starts_at <= ^now)
    |> where([announcement], is_nil(announcement.expires_at) or announcement.expires_at > ^now)
    |> maybe_owner(owner_kind)
    |> order_by([announcement], asc: announcement.inserted_at)
    |> Repo.all()
  end

  def create_board(attrs) do
    payload_hash = payload_hash(attrs)

    case Repo.get(ForumHostAcceptedIntent, attrs.intent_id) do
      %ForumHostAcceptedIntent{payload_hash: ^payload_hash, result_id: result_id} ->
        {:ok, Repo.get!(ForumHostBoard, result_id)}

      %ForumHostAcceptedIntent{} ->
        {:error, :duplicate_intent}

      nil ->
        insert_board(attrs, payload_hash)
    end
  end

  def forum_host_id do
    Application.get_env(:ansible_relay, :forum_host_id, "host-local-dev")
  end

  def base_url do
    Application.get_env(:ansible_relay, :forum_host_base_url, @default_base_url)
  end

  defp insert_board(attrs, payload_hash) do
    slug = unique_slug(slugify(attrs.title))
    hosted_board_id = slug

    Repo.transaction(fn ->
      board =
        %ForumHostBoard{}
        |> ForumHostBoard.changeset(%{
          hosted_board_id: hosted_board_id,
          slug: slug,
          canonical_board_uri: "#{base_url()}/boards/#{slug}",
          title: attrs.title,
          description: Map.get(attrs, :description),
          language: Map.get(attrs, :language),
          tags: Map.get(attrs, :tags, []),
          permissions: Map.get(attrs, :permissions, %{"read" => true, "write" => true}),
          posting_policy: Map.get(attrs, :posting_policy, posting_policy()),
          moderation_policy: Map.get(attrs, :moderation_policy, moderation_policy())
        })
        |> Repo.insert!()

      %ForumHostAcceptedIntent{}
      |> ForumHostAcceptedIntent.changeset(%{
        intent_id: attrs.intent_id,
        author_did: attrs.author_did,
        action: "create_board",
        payload_hash: payload_hash,
        result_kind: "forum_host_board",
        result_id: board.hosted_board_id,
        accepted_at: DateTime.utc_now()
      })
      |> Repo.insert!()

      board
    end)
  end

  defp upsert_seed_board(attrs) do
    slug = Map.fetch!(attrs, "slug")
    hosted_board_id = Map.get(attrs, "hosted_board_id", slug)

    changes =
      attrs
      |> Map.put("hosted_board_id", hosted_board_id)
      |> Map.put("canonical_board_uri", Map.get(attrs, "canonical_board_uri", "#{base_url()}/boards/#{slug}"))

    %ForumHostBoard{}
    |> ForumHostBoard.changeset(changes)
    |> Repo.insert(
      on_conflict: {:replace, [
        :slug,
        :canonical_board_uri,
        :title,
        :description,
        :language,
        :tags,
        :permissions,
        :posting_policy,
        :moderation_policy,
        :updated_at
      ]},
      conflict_target: :hosted_board_id
    )
  end

  defp upsert_seed_announcement(attrs) do
    %ForumHostAnnouncement{}
    |> ForumHostAnnouncement.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [
        :owner_kind,
        :hosted_board_id,
        :title,
        :body,
        :severity,
        :locale,
        :url,
        :starts_at,
        :expires_at,
        :updated_at
      ]},
      conflict_target: :announcement_id
    )
  end

  defp maybe_owner(query, nil), do: query
  defp maybe_owner(query, owner_kind), do: where(query, [announcement], announcement.owner_kind == ^owner_kind)

  defp seed_boards do
    Application.get_env(:ansible_relay, :forum_host_seed_boards, [
      %{
        "hosted_board_id" => "general",
        "slug" => "general",
        "title" => "General",
        "description" => "General discussion",
        "language" => "en",
        "tags" => ["starter"],
        "permissions" => %{"read" => true, "write" => true},
        "posting_policy" => posting_policy(),
        "moderation_policy" => moderation_policy()
      }
    ])
  end

  defp seed_announcements do
    Application.get_env(:ansible_relay, :forum_host_announcements, [])
  end

  defp display_name do
    Application.get_env(:ansible_relay, :forum_host_display_name, "Local Forum Host")
  end

  defp constitution_compliance do
    Application.get_env(:ansible_relay, :forum_host_constitution_compliance, "unknown")
  end

  defp host_public_keys do
    Application.get_env(:ansible_relay, :forum_host_public_keys, [])
  end

  defp accepted_session_issuers do
    Application.get_env(:ansible_relay, :forum_host_accepted_session_issuers, [
      %{"issuer" => Application.get_env(:ansible_relay, :relay_origin, base_url())}
    ])
  end

  defp rules do
    Application.get_env(:ansible_relay, :forum_host_rules, %{
      "summary" => "Be relevant, lawful, and respectful of board rules."
    })
  end

  defp posting_policy do
    Application.get_env(:ansible_relay, :forum_host_posting_policy, %{
      "min_trust_tier" => "self_custody_did"
    })
  end

  defp moderation_policy do
    Application.get_env(:ansible_relay, :forum_host_moderation_policy, %{
      "reason_codes" => ["spam", "abuse", "illegal", "off_topic"],
      "appeals" => true
    })
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "board"
      slug -> slug
    end
  end

  defp unique_slug(slug) do
    if Repo.get_by(ForumHostBoard, slug: slug), do: "#{slug}-#{System.unique_integer([:positive])}", else: slug
  end

  defp payload_hash(attrs) do
    attrs
    |> Map.take([:intent_id, :author_did, :title, :description])
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
```

- [ ] **Step 6: Run migration and store tests**

Run:

```bash
cd ansible_relay/phoenix
mix ecto.migrate
mix test test/forum_host_store_test.exs
```

Expected: `mix ecto.migrate` succeeds and `mix test test/forum_host_store_test.exs`
passes.

- [ ] **Step 7: Commit Task 1**

```bash
git add ansible_relay/phoenix/priv/repo/migrations/20260602000001_create_forum_host_tables.exs \
  ansible_relay/phoenix/lib/ansible_relay/db/forum_host_board.ex \
  ansible_relay/phoenix/lib/ansible_relay/db/forum_host_announcement.ex \
  ansible_relay/phoenix/lib/ansible_relay/db/forum_host_accepted_intent.ex \
  ansible_relay/phoenix/lib/ansible_relay/forum_host/store.ex \
  ansible_relay/phoenix/test/forum_host_store_test.exs
git commit -m "Add durable forum host store"
```

## Task 2: Forum Host Discovery Endpoints

**Files:**
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`
- Modify: `ansible_relay/phoenix/test/forum_host_controller_test.exs`

- [ ] **Step 1: Write failing controller tests**

Add these tests to `ansible_relay/phoenix/test/forum_host_controller_test.exs`:

```elixir
test "GET /api/v1/forum-host exposes compliance, policy, host identity, and issuers" do
  response = get_json("/api/v1/forum-host")
  assert response.status == 200

  body = Jason.decode!(response.resp_body)
  assert body["forum_host_id"] == "host-local-dev"
  assert body["server_kind"] == "ansibleForumHost"
  assert body["constitution_compliance"] in ["unknown", "compatible", "constitution_compliant"]
  assert is_map(body["rules"])
  assert is_map(body["posting_policy"])
  assert is_map(body["moderation_policy"])
  assert is_list(body["host_public_keys"])
  assert is_list(body["accepted_session_issuers"])
  assert body["capabilities"]["announcements"] == true
end

test "GET /api/v1/forum-host/announcements returns host-owned announcements" do
  original_announcements = Application.get_env(:ansible_relay, :forum_host_announcements)

  Application.put_env(:ansible_relay, :forum_host_announcements, [
    %{
      "announcement_id" => "host-rules",
      "owner_kind" => "forum_host",
      "title" => "Rules updated",
      "body" => "Posting policy was refreshed.",
      "severity" => "info",
      "locale" => "en"
    }
  ])

  on_exit(fn ->
    if original_announcements do
      Application.put_env(:ansible_relay, :forum_host_announcements, original_announcements)
    else
      Application.delete_env(:ansible_relay, :forum_host_announcements)
    end
  end)

  response = get_json("/api/v1/forum-host/announcements")
  assert response.status == 200

  body = Jason.decode!(response.resp_body)
  assert [%{"announcement_id" => "host-rules", "owner_kind" => "forum_host"}] =
           body["announcements"]
end
```

- [ ] **Step 2: Run controller tests and verify they fail**

Run:

```bash
cd ansible_relay/phoenix
mix test test/forum_host_controller_test.exs
```

Expected: failure because the response is missing new fields and
`/api/v1/forum-host/announcements` is not routed.

- [ ] **Step 3: Add announcements route**

Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex` after the
`/api/v1/forum-host/boards` read route:

```elixir
  get "/api/v1/forum-host/announcements" do
    AnsibleRelay.Web.Controllers.ForumHostController.announcements(conn, conn.query_params)
  end
```

- [ ] **Step 4: Update ForumHostController discovery reads**

Modify `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`:

```elixir
defmodule AnsibleRelay.Web.Controllers.ForumHostController do
  @moduledoc "Co-located Forum Host discovery and write surface."

  import Plug.Conn

  alias AnsibleRelay.AbuseDetector
  alias AnsibleRelay.ForumHost.Store
  alias AnsibleRelay.Web.Plugs.VerifyWebSession

  def info(conn, _params) do
    send_json(conn, 200, Store.host_info())
  end

  def boards(conn, _params) do
    send_json(conn, 200, %{boards: Store.list_boards()})
  end

  def announcements(conn, _params) do
    send_json(conn, 200, %{announcements: Store.list_announcements("forum_host")})
  end

  # Keep create_board and create_web_thread in place for now. Task 4 replaces
  # create_board auth with signed-intent verification.
```

Keep the existing `create_board/2`, `create_web_thread/2`, `send_json/3`, and
helper functions until Task 4 replaces the legacy starter-board placeholder path.

- [ ] **Step 5: Run controller tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/forum_host_controller_test.exs
```

Expected: all existing Forum Host controller tests pass except create-board
tests that still expect the old hard-coded create response. If a create-board
test fails because `Store.list_boards()` seeded data changed ordering, update the
assertion to select the board by `hosted_board_id`.

- [ ] **Step 6: Commit Task 2**

```bash
git add ansible_relay/phoenix/lib/ansible_relay/web/router.ex \
  ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex \
  ansible_relay/phoenix/test/forum_host_controller_test.exs
git commit -m "Expose forum host discovery metadata"
```

## Task 3: Elix Relay Discovery Endpoint

**Files:**
- Create: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/relay_discovery_controller.ex`
- Create: `ansible_relay/phoenix/test/relay_discovery_controller_test.exs`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`

- [ ] **Step 1: Write failing Relay discovery tests**

Create `ansible_relay/phoenix/test/relay_discovery_controller_test.exs`:

```elixir
defmodule AnsibleRelay.Web.RelayDiscoveryControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    original_relay_origin = Application.get_env(:ansible_relay, :relay_origin)
    original_announcements = Application.get_env(:ansible_relay, :relay_announcements)
    original_featured = Application.get_env(:ansible_relay, :relay_featured_boards)

    Application.put_env(:ansible_relay, :relay_origin, "https://relay.trisaura.test")
    Application.put_env(:ansible_relay, :relay_announcements, [
      %{
        "announcement_id" => "relay-status",
        "owner_kind" => "relay",
        "title" => "Relay online",
        "body" => "Relay discovery is available.",
        "severity" => "info",
        "locale" => "en"
      }
    ])
    Application.put_env(:ansible_relay, :relay_featured_boards, [
      %{
        "forum_host_url" => "https://forum.trisaura.test",
        "canonical_board_uri" => "https://forum.trisaura.test/boards/general",
        "hosted_board_id" => "general",
        "title" => "General",
        "description" => "Start here"
      }
    ])

    on_exit(fn ->
      restore_env(:relay_origin, original_relay_origin)
      restore_env(:relay_announcements, original_announcements)
      restore_env(:relay_featured_boards, original_featured)
    end)

    :ok
  end

  test "GET /api/v1/discovery returns Relay bootstrap catalog" do
    response =
      conn(:get, "/api/v1/discovery")
      |> Router.call(@router_opts)

    assert response.status == 200
    body = Jason.decode!(response.resp_body)

    assert body["version"] == 1
    assert body["relay"]["origin"] == "https://relay.trisaura.test"
    assert body["relay"]["server_kind"] == "elixRelay"
    assert [%{"announcement_id" => "relay-status", "owner_kind" => "relay"}] =
             body["announcements"]
    assert [%{"hosted_board_id" => "general"}] = body["featured_boards"]
    assert is_list(body["featured_forum_hosts"])
    assert is_map(body["cache"])
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
```

- [ ] **Step 2: Run Relay discovery test and verify it fails**

Run:

```bash
cd ansible_relay/phoenix
mix test test/relay_discovery_controller_test.exs
```

Expected: `404` or compile failure because the controller/route does not exist.

- [ ] **Step 3: Add controller**

Create `ansible_relay/phoenix/lib/ansible_relay/web/controllers/relay_discovery_controller.ex`:

```elixir
defmodule AnsibleRelay.Web.Controllers.RelayDiscoveryController do
  @moduledoc "App-facing Elix Relay bootstrap discovery."

  import Plug.Conn

  alias AnsibleRelay.ForumHost.Store

  def show(conn, _params) do
    send_json(conn, 200, %{
      version: 1,
      relay: relay_info(),
      announcements: relay_announcements(),
      featured_forum_hosts: featured_forum_hosts(),
      featured_boards: featured_boards(),
      cache: %{
        max_age_seconds: Application.get_env(:ansible_relay, :relay_discovery_max_age_seconds, 300)
      }
    })
  end

  defp relay_info do
    %{
      server_kind: "elixRelay",
      origin: Application.get_env(:ansible_relay, :relay_origin, "http://localhost:4001"),
      capabilities: %{
        forum_host_discovery: true,
        relay_announcements: true,
        web_sessions: true
      }
    }
  end

  defp relay_announcements do
    Application.get_env(:ansible_relay, :relay_announcements, [])
  end

  defp featured_forum_hosts do
    Application.get_env(:ansible_relay, :relay_featured_forum_hosts, [
      %{
        "forum_host_id" => Store.forum_host_id(),
        "display_name" => Store.host_info().display_name,
        "forum_host_url" => Store.base_url(),
        "constitution_compliance" => Store.host_info().constitution_compliance
      }
    ])
  end

  defp featured_boards do
    configured = Application.get_env(:ansible_relay, :relay_featured_boards, nil)

    if configured do
      configured
    else
      Store.list_boards()
      |> Enum.map(fn board ->
        %{
          hosted_board_id: board.hosted_board_id,
          title: board.title,
          description: board.description,
          forum_host_url: Store.base_url(),
          canonical_board_uri: board.canonical_board_uri,
          constitution_compliance: Store.host_info().constitution_compliance,
          tags: board.tags,
          language: board.language
        }
      end)
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
```

- [ ] **Step 4: Add route**

Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex` after
`/health`:

```elixir
  get "/api/v1/discovery" do
    AnsibleRelay.Web.Controllers.RelayDiscoveryController.show(conn, conn.query_params)
  end
```

- [ ] **Step 5: Run Relay discovery tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/relay_discovery_controller_test.exs
```

Expected: tests pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add ansible_relay/phoenix/lib/ansible_relay/web/controllers/relay_discovery_controller.ex \
  ansible_relay/phoenix/lib/ansible_relay/web/router.ex \
  ansible_relay/phoenix/test/relay_discovery_controller_test.exs
git commit -m "Add relay discovery endpoint"
```

## Task 4: App Signed-Intent Forum Host Writes

**Files:**
- Create: `ansible_relay/phoenix/lib/ansible_relay/forum_host/signed_intent.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`
- Modify: `ansible_relay/phoenix/test/forum_host_controller_test.exs`

- [ ] **Step 1: Add failing signed-intent controller tests**

Add helpers and tests to `ansible_relay/phoenix/test/forum_host_controller_test.exs`:

```elixir
defp ed25519_keypair do
  {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
  {Base.encode16(public_key, case: :lower), private_key}
end

defp sign(private_key, message) do
  :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
  |> Base.encode16(case: :lower)
end

defp signed_create_board_intent(did, private_key, attrs \\ %{}) do
  payload =
    Map.merge(
      %{
        "type" => "io.trisaura.forum.createBoard",
        "version" => 1,
        "intent_id" => "intent-#{System.unique_integer([:positive])}",
        "author_did" => did,
        "target_forum_host" => "http://localhost:4001",
        "action" => "create_board",
        "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "expires_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 300, :second)),
        "board" => %{
          "title" => "Signed Reading",
          "description" => "Signed board"
        }
      },
      attrs
    )

  Map.put(payload, "signature", sign(private_key, AnsibleRelay.ForumHost.SignedIntent.canonical_json(payload)))
end

test "POST /api/v1/forum-host/boards accepts app DID signed intent without web session" do
  {public_key_hex, private_key} = ed25519_keypair()
  did = "did:plc:signedboard123"
  :ok = AnsibleRelay.IdentityCache.put(did, public_key_hex)

  response =
    post_json(
      "/api/v1/forum-host/boards",
      signed_create_board_intent(did, private_key),
      []
    )

  assert response.status == 201
  body = Jason.decode!(response.resp_body)
  assert body["hosted_board_id"] == "signed-reading"
  assert body["title"] == "Signed Reading"
end

test "POST /api/v1/forum-host/boards rejects tampered signed intent" do
  {public_key_hex, private_key} = ed25519_keypair()
  did = "did:plc:tamperboard123"
  :ok = AnsibleRelay.IdentityCache.put(did, public_key_hex)

  body =
    did
    |> signed_create_board_intent(private_key)
    |> put_in(["board", "title"], "Tampered Title")

  response = post_json("/api/v1/forum-host/boards", body, [])

  assert response.status == 401
  assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
end

test "POST /api/v1/forum-host/boards rejects unsigned author DID" do
  response =
    post_json(
      "/api/v1/forum-host/boards",
      %{
        "intent_id" => "legacy-intent",
        "author_did" => "did:plc:unsigned",
        "board" => %{"title" => "Unsigned"}
      },
      []
    )

  assert response.status == 401
  assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
end
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
cd ansible_relay/phoenix
mix test test/forum_host_controller_test.exs
```

Expected: compile failure because `AnsibleRelay.ForumHost.SignedIntent` does
not exist, or test failure because create-board still requires a web session.

- [ ] **Step 3: Add signed intent verifier**

Create `ansible_relay/phoenix/lib/ansible_relay/forum_host/signed_intent.ex`:

```elixir
defmodule AnsibleRelay.ForumHost.SignedIntent do
  @moduledoc "Canonical JSON and verification for app-originated Forum Host intents."

  alias AnsibleRelay.{IdentityCache, SigVerifier}
  alias AnsibleRelay.ForumHost.Store

  def verify_create_board(params) do
    with :ok <- require_string(params, "signature"),
         :ok <- require_string(params, "author_did"),
         :ok <- require_string(params, "intent_id"),
         :ok <- require_string(params, "target_forum_host"),
         :ok <- require_string(params, "action"),
         :ok <- require_board_title(params),
         :ok <- require_type(params, "io.trisaura.forum.createBoard"),
         :ok <- require_version(params, 1),
         :ok <- require_action(params, "create_board"),
         :ok <- require_target_host(params["target_forum_host"]),
         :ok <- require_not_expired(params["expires_at"]),
         {:ok, public_key_hex} <- public_key(params["author_did"]),
         true <- SigVerifier.verify_ed25519(public_key_hex, canonical_json(params), params["signature"]) do
      {:ok,
       %{
         intent_id: params["intent_id"],
         author_did: params["author_did"],
         title: params["board"]["title"],
         description: params["board"]["description"]
       }}
    else
      false -> {:error, :invalid_signature}
      {:error, error} -> {:error, error}
    end
  end

  def canonical_json(value) when is_map(value) do
    value
    |> Map.delete("signature")
    |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
    |> Enum.sort_by(fn {key, _entry_value} -> key end)
    |> Enum.map(fn {key, entry_value} ->
      Jason.encode!(key) <> ":" <> canonical_json(entry_value)
    end)
    |> then(&("{" <> Enum.join(&1, ",") <> "}"))
  end

  def canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  def canonical_json(value), do: Jason.encode!(value)

  defp require_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, :"missing_#{key}"}, else: :ok

      _ ->
        {:error, :"missing_#{key}"}
    end
  end

  defp require_board_title(%{"board" => %{"title" => title}}) when is_binary(title) do
    if String.trim(title) == "", do: {:error, :invalid_board}, else: :ok
  end

  defp require_board_title(_params), do: {:error, :invalid_board}

  defp require_type(%{"type" => expected}, expected), do: :ok
  defp require_type(_params, _expected), do: {:error, :invalid_intent_type}

  defp require_version(%{"version" => expected}, expected), do: :ok
  defp require_version(_params, _expected), do: {:error, :invalid_intent_version}

  defp require_action(%{"action" => expected}, expected), do: :ok
  defp require_action(_params, _expected), do: {:error, :invalid_action}

  defp require_target_host(target) do
    if normalize_origin(target) == normalize_origin(Store.base_url()),
      do: :ok,
      else: {:error, :audience_mismatch}
  end

  defp require_not_expired(expires_at) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, parsed, _offset} ->
        if DateTime.compare(DateTime.utc_now(), parsed) == :lt,
          do: :ok,
          else: {:error, :expired_intent}

      _ ->
        {:error, :invalid_expiry}
    end
  end

  defp require_not_expired(_expires_at), do: {:error, :invalid_expiry}

  defp public_key(did) do
    case IdentityCache.public_key_hex(did) do
      nil -> {:error, :unknown_did}
      public_key_hex -> {:ok, public_key_hex}
    end
  end

  defp normalize_origin(value) do
    uri = URI.parse(value)
    port = if uri.port, do: ":#{uri.port}", else: ""
    "#{String.downcase(uri.scheme || "")}://#{String.downcase(uri.host || "")}#{port}"
  end
end
```

- [ ] **Step 4: Update create-board controller auth**

Modify `create_board/2` in `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`:

```elixir
  alias AnsibleRelay.ForumHost.{SignedIntent, Store}

  def create_board(conn, params) do
    case SignedIntent.verify_create_board(params) do
      {:ok, intent} ->
        case Store.create_board(intent) do
          {:ok, board} -> send_json(conn, 201, board)
          {:error, :duplicate_intent} -> send_json(conn, 409, %{error: "duplicate_intent"})
        end

      {:error, :audience_mismatch} ->
        send_json(conn, 403, %{error: "audience_mismatch"})

      {:error, error}
      when error in [:invalid_signature, :unknown_did, :missing_signature] ->
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, error} ->
        send_json(conn, 422, %{error: to_string(error)})
    end
  end
```

Remove the old `require_fields/2`, `check_author_matches_session/2`, and
`slugify/1` helpers if no code uses them.

- [ ] **Step 5: Run signed-intent tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/forum_host_controller_test.exs
```

Expected: signed-intent tests pass. Update the older create-board test to use
`signed_create_board_intent/3` instead of a web session token.

- [ ] **Step 6: Commit Task 4**

```bash
git add ansible_relay/phoenix/lib/ansible_relay/forum_host/signed_intent.ex \
  ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex \
  ansible_relay/phoenix/test/forum_host_controller_test.exs
git commit -m "Verify forum host signed intents"
```

## Task 5: Web Session Cookie And Audience Verification

**Files:**
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/plugs/verify_web_session.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`
- Modify: `ansible_relay/phoenix/test/web_session_controller_test.exs`
- Modify: `ansible_relay/phoenix/test/verify_web_session_test.exs`
- Modify: `ansible_relay/phoenix/test/forum_host_controller_test.exs`

- [ ] **Step 1: Write failing web-session audience and cookie tests**

Add to `ansible_relay/phoenix/test/verify_web_session_test.exs`:

```elixir
test "valid cookie token assigns web session" do
  session = approved_session(["forum:post"])

  conn =
    conn(:post, "/")
    |> put_req_cookie("trisaura_session", session.session_token)
    |> VerifyWebSession.call(["forum:post"])

  refute conn.halted
  assert conn.assigns.web_session.session_token == session.session_token
end

test "wrong required audience returns 403" do
  session = approved_session(["forum:post"])

  conn =
    conn(:post, "/")
    |> put_req_header("authorization", "Bearer #{session.session_token}")
    |> VerifyWebSession.call(["forum:post"], audience: "https://other-host.test")

  assert conn.status == 403
  assert Jason.decode!(conn.resp_body)["error"] == "audience_mismatch"
end
```

Add to `ansible_relay/phoenix/test/web_session_controller_test.exs`:

```elixir
test "approved challenge persists audience into session response" do
  {public_key_hex, private_key} = ed25519_keypair()
  did = "did:plc:audience23456789"
  :ok = IdentityCache.put(did, public_key_hex)

  challenge_response =
    post_json("/api/v1/web-sessions/challenges", %{
      "web_origin" => "https://trisaura.io",
      "relay_origin" => "https://relay.trisaura.io",
      "audience" => "http://localhost:4001",
      "scopes" => ["forum:post"]
    })

  challenge = Jason.decode!(challenge_response.resp_body)
  stored_challenge = WebSessionStore.get_challenge(challenge["challenge_id"]) |> elem(1)
  grant = grant(stored_challenge, did) |> Map.put("audience", "http://localhost:4001")
  signature = sign(private_key, canonical_json(grant))

  response =
    post_json("/api/v1/web-sessions/approve", %{
      "challenge_id" => challenge["challenge_id"],
      "subject_did" => did,
      "grant" => grant,
      "signature" => signature
    })

  assert response.status == 200
  body = Jason.decode!(response.resp_body)
  assert body["audience"] == "http://localhost:4001"
end
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
cd ansible_relay/phoenix
mix test test/verify_web_session_test.exs test/web_session_controller_test.exs
```

Expected: failures because cookie tokens and audience are not supported.

- [ ] **Step 3: Store audience in WebSessionStore**

Modify the session map in
`ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`:

```elixir
challenge = %{
  challenge_id: token("wsc"),
  web_origin: string_attr(attrs, "web_origin"),
  relay_origin: string_attr(attrs, "relay_origin"),
  audience: string_attr(attrs, "audience") || string_attr(attrs, "relay_origin"),
  scopes: list_attr(attrs, "scopes"),
  status: "pending",
  created_at: now,
  expires_at: DateTime.add(now, ttl_seconds, :second),
  approved_session_token: nil
}
```

Add `audience` to the approved session:

```elixir
session = %{
  session_token: token("wst"),
  subject_did: subject_did,
  approving_device_id: approving_device_id,
  web_origin: challenge.web_origin,
  relay_origin: challenge.relay_origin,
  audience: challenge.audience,
  scopes: scopes,
  trust_tier: @trust_tier,
  expires_at: expires_at,
  created_at: now,
  revoked_at: nil
}
```

- [ ] **Step 4: Validate audience in WebSessionController**

Modify `create_challenge/2` in
`ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex`
to parse an optional audience:

```elixir
with {:ok, web_origin} <- validate_web_origin(params["web_origin"]),
     {:ok, relay_origin} <- validate_relay_origin(params["relay_origin"]),
     {:ok, audience} <- validate_audience(params["audience"] || params["relay_origin"]),
     {:ok, scopes} <- validate_scopes(params["scopes"]),
     :ok <- check_challenge_rate_limit(conn),
     ttl_seconds <- challenge_ttl(params["ttl_seconds"]),
     {:ok, challenge} <-
       WebSessionStore.issue_challenge(%{
         "web_origin" => web_origin,
         "relay_origin" => relay_origin,
         "audience" => audience,
         "scopes" => scopes,
         "ttl_seconds" => ttl_seconds
       }) do
```

Add `audience` to `validate_grant/3`:

```elixir
grant["audience"] != challenge.audience ->
  {:error, :audience_mismatch}
```

Add helper near origin validation:

```elixir
defp validate_audience(value) when is_binary(value) do
  case URI.parse(value) do
    %URI{scheme: scheme, host: host} when scheme in ["https", "http"] and is_binary(host) ->
      {:ok, normalize_origin(value)}

    _ ->
      {:error, :invalid_audience}
  end
end

defp validate_audience(_value), do: {:error, :invalid_audience}
```

Add `audience` to `challenge_response/1` and `session_response/2`:

```elixir
audience: challenge.audience
```

```elixir
audience: session.audience
```

- [ ] **Step 5: Accept bearer or cookie in VerifyWebSession and check audience**

Modify `ansible_relay/phoenix/lib/ansible_relay/web/plugs/verify_web_session.ex`:

```elixir
def call(conn, required_scopes, opts \\ []) when is_list(required_scopes) do
  with {:ok, token} <- session_token(conn),
       {:ok, session} <- WebSessionStore.get_session(token),
       :ok <- require_scopes(session.scopes, required_scopes),
       :ok <- require_audience(session, Keyword.get(opts, :audience)) do
    conn
    |> assign(:web_session, session)
    |> assign(:verified_did, session.subject_did)
  else
    {:error, :missing_scope} ->
      send_error(conn, 403, "missing_required_scope")

    {:error, :audience_mismatch} ->
      send_error(conn, 403, "audience_mismatch")

    _ ->
      send_error(conn, 401, "invalid_web_session")
  end
end

defp session_token(conn) do
  case get_req_header(conn, "authorization") do
    ["Bearer " <> token] when token != "" ->
      {:ok, token}

    _ ->
      case conn.req_cookies["trisaura_session"] do
        token when is_binary(token) and token != "" -> {:ok, token}
        _ -> {:error, :missing_token}
      end
  end
end

defp require_audience(_session, nil), do: :ok

defp require_audience(%{audience: audience}, required_audience) do
  if normalize_origin(audience) == normalize_origin(required_audience),
    do: :ok,
    else: {:error, :audience_mismatch}
end
```

Add `normalize_origin/1` in the same module:

```elixir
defp normalize_origin(value) do
  uri = URI.parse(value || "")
  port = if uri.port, do: ":#{uri.port}", else: ""
  "#{String.downcase(uri.scheme || "")}://#{String.downcase(uri.host || "")}#{port}"
end
```

- [ ] **Step 6: Require Forum Host audience for web thread writes**

Modify `create_web_thread/2` in
`ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`:

```elixir
conn = VerifyWebSession.call(conn, ["forum:post"], audience: Store.base_url())
```

- [ ] **Step 7: Run session tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/verify_web_session_test.exs test/web_session_controller_test.exs test/forum_host_controller_test.exs
```

Expected: tests pass.

- [ ] **Step 8: Commit Task 5**

```bash
git add ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex \
  ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex \
  ansible_relay/phoenix/lib/ansible_relay/web/plugs/verify_web_session.ex \
  ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex \
  ansible_relay/phoenix/test/web_session_controller_test.exs \
  ansible_relay/phoenix/test/verify_web_session_test.exs \
  ansible_relay/phoenix/test/forum_host_controller_test.exs
git commit -m "Add audience-aware web session auth"
```

## Task 6: App Clients For Discovery And Signed Board Creation

**Files:**
- Create: `ansible_node/app/lib/services/relay_discovery_client.dart`
- Create: `ansible_node/app/test/relay_discovery_client_test.dart`
- Modify: `ansible_node/app/lib/services/forum_host_client.dart`
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
- Modify: `ansible_node/app/test/forum_host_client_test.dart`

- [ ] **Step 1: Write failing RelayDiscoveryClient tests**

Create `ansible_node/app/test/relay_discovery_client_test.dart`:

```dart
import 'dart:convert';

import 'package:ansible_node/services/relay_discovery_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchDiscovery reads Relay bootstrap catalog', () async {
    final client = RelayDiscoveryClient(
      baseUrl: 'http://relay.local/root',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'http://relay.local/root/api/v1/discovery');
        return http.Response(
          jsonEncode({
            'version': 1,
            'relay': {'server_kind': 'elixRelay', 'origin': 'http://relay.local'},
            'announcements': [
              {
                'announcement_id': 'relay-status',
                'owner_kind': 'relay',
                'title': 'Relay online',
                'body': 'Discovery ready',
                'severity': 'info',
              }
            ],
            'featured_forum_hosts': [
              {
                'forum_host_id': 'host-local-dev',
                'display_name': 'Local Forum Host',
                'forum_host_url': 'http://relay.local',
                'constitution_compliance': 'unknown',
              }
            ],
            'featured_boards': [
              {
                'hosted_board_id': 'general',
                'title': 'General',
                'forum_host_url': 'http://relay.local',
                'canonical_board_uri': 'http://relay.local/boards/general',
              }
            ],
            'cache': {'max_age_seconds': 300},
          }),
          200,
        );
      }),
    );

    final discovery = await client.fetchDiscovery();

    expect(discovery.version, 1);
    expect(discovery.relay.origin, 'http://relay.local');
    expect(discovery.announcements.single.ownerKind, 'relay');
    expect(discovery.featuredForumHosts.single.constitutionCompliance, 'unknown');
    expect(discovery.featuredBoards.single.hostedBoardId, 'general');
  });
}
```

- [ ] **Step 2: Run app discovery test and verify it fails**

Run:

```bash
cd ansible_node/app
flutter test test/relay_discovery_client_test.dart
```

Expected: compile failure because `RelayDiscoveryClient` does not exist.

- [ ] **Step 3: Add RelayDiscoveryClient**

Create `ansible_node/app/lib/services/relay_discovery_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'relay_identity_client.dart';

class RelayDiscoveryClient {
  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  RelayDiscoveryClient({
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  Future<RelayDiscovery> fetchDiscovery() async {
    final response = await _client.get(_endpoint('/api/v1/discovery')).timeout(timeout);
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RelayDiscoveryException(response.statusCode, decoded is Map<String, dynamic> ? decoded : const {});
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected discovery JSON object');
    }
    return RelayDiscovery.fromJson(decoded);
  }

  Uri _endpoint(String path) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$basePath$path');
  }

  void close() => _client.close();
}

class RelayDiscoveryException implements Exception {
  final int statusCode;
  final Map<String, dynamic> body;

  const RelayDiscoveryException(this.statusCode, this.body);
}

class RelayDiscovery {
  final int version;
  final RelayDiscoveryRelay relay;
  final List<RelayAnnouncement> announcements;
  final List<DiscoveredForumHost> featuredForumHosts;
  final List<DiscoveredBoard> featuredBoards;

  const RelayDiscovery({
    required this.version,
    required this.relay,
    required this.announcements,
    required this.featuredForumHosts,
    required this.featuredBoards,
  });

  factory RelayDiscovery.fromJson(Map<String, dynamic> json) {
    return RelayDiscovery(
      version: json['version'] as int,
      relay: RelayDiscoveryRelay.fromJson(Map<String, dynamic>.from(json['relay'] as Map)),
      announcements: _list(json['announcements']).map(RelayAnnouncement.fromJson).toList(growable: false),
      featuredForumHosts: _list(json['featured_forum_hosts']).map(DiscoveredForumHost.fromJson).toList(growable: false),
      featuredBoards: _list(json['featured_boards']).map(DiscoveredBoard.fromJson).toList(growable: false),
    );
  }
}

class RelayDiscoveryRelay {
  final String serverKind;
  final String origin;

  const RelayDiscoveryRelay({required this.serverKind, required this.origin});

  factory RelayDiscoveryRelay.fromJson(Map<String, dynamic> json) {
    return RelayDiscoveryRelay(
      serverKind: json['server_kind'] as String,
      origin: json['origin'] as String,
    );
  }
}

class RelayAnnouncement {
  final String announcementId;
  final String ownerKind;
  final String title;
  final String body;
  final String severity;

  const RelayAnnouncement({
    required this.announcementId,
    required this.ownerKind,
    required this.title,
    required this.body,
    required this.severity,
  });

  factory RelayAnnouncement.fromJson(Map<String, dynamic> json) {
    return RelayAnnouncement(
      announcementId: json['announcement_id'] as String,
      ownerKind: json['owner_kind'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      severity: json['severity'] as String? ?? 'info',
    );
  }
}

class DiscoveredForumHost {
  final String forumHostId;
  final String displayName;
  final String forumHostUrl;
  final String constitutionCompliance;

  const DiscoveredForumHost({
    required this.forumHostId,
    required this.displayName,
    required this.forumHostUrl,
    required this.constitutionCompliance,
  });

  factory DiscoveredForumHost.fromJson(Map<String, dynamic> json) {
    return DiscoveredForumHost(
      forumHostId: json['forum_host_id'] as String,
      displayName: json['display_name'] as String,
      forumHostUrl: json['forum_host_url'] as String,
      constitutionCompliance: json['constitution_compliance'] as String? ?? 'unknown',
    );
  }
}

class DiscoveredBoard {
  final String hostedBoardId;
  final String title;
  final String forumHostUrl;
  final String canonicalBoardUri;

  const DiscoveredBoard({
    required this.hostedBoardId,
    required this.title,
    required this.forumHostUrl,
    required this.canonicalBoardUri,
  });

  factory DiscoveredBoard.fromJson(Map<String, dynamic> json) {
    return DiscoveredBoard(
      hostedBoardId: json['hosted_board_id'] as String,
      title: json['title'] as String,
      forumHostUrl: json['forum_host_url'] as String,
      canonicalBoardUri: json['canonical_board_uri'] as String,
    );
  }
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
}
```

- [ ] **Step 4: Write failing signed create-board client test**

Modify `ansible_node/app/test/forum_host_client_test.dart` create-board test to
expect canonical fields:

```dart
expect(body['type'], 'io.trisaura.forum.createBoard');
expect(body['version'], 1);
expect(body['target_forum_host'], 'http://relay.local');
expect(body['action'], 'create_board');
expect(body['created_at'], isA<String>());
expect(body['expires_at'], isA<String>());
expect(body['signature'], 'sig-hex');
```

- [ ] **Step 5: Update ForumHostClient create-board intent**

Modify `ansible_node/app/lib/services/forum_host_client.dart`:

```dart
class CreateHostedBoardIntent {
  static const type = 'io.trisaura.forum.createBoard';
  static const version = 1;

  final String intentId;
  final String authorDid;
  final String targetForumHost;
  final String signature;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime expiresAt;

  const CreateHostedBoardIntent({
    required this.intentId,
    required this.authorDid,
    required this.targetForumHost,
    required this.signature,
    required this.title,
    required this.createdAt,
    required this.expiresAt,
    this.description,
  });

  static Map<String, Object?> canonicalPayload({
    required String intentId,
    required String authorDid,
    required String targetForumHost,
    required String title,
    required DateTime createdAt,
    required DateTime expiresAt,
    String? description,
  }) {
    return {
      'action': 'create_board',
      'author_did': authorDid,
      'board': {
        if (description != null && description.isNotEmpty) 'description': description,
        'title': title,
      },
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'intent_id': intentId,
      'target_forum_host': targetForumHost,
      'type': type,
      'version': version,
    };
  }

  Map<String, Object?> toJson() {
    return {
      ...canonicalPayload(
        intentId: intentId,
        authorDid: authorDid,
        targetForumHost: targetForumHost,
        title: title,
        description: description,
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
      'signature': signature,
    };
  }
}
```

- [ ] **Step 6: Update home_shell signing**

Modify `_createBoard()` in `ansible_node/app/lib/screens/home_shell.dart`:

```dart
final createdAt = now.toUtc();
final expiresAt = createdAt.add(const Duration(minutes: 5));
final canonicalPayload = CreateHostedBoardIntent.canonicalPayload(
  intentId: intentId,
  authorDid: widget.did,
  targetForumHost: forumHost.url,
  title: title,
  description: result['description'],
  createdAt: createdAt,
  expiresAt: expiresAt,
);
final signature = await DidSignerImpl()
    .sign(utf8.encode(jsonEncode(canonicalPayload)))
    .then((signature) => signature.hex);
final remoteBoard = await ForumHostClient(baseUrl: forumHost.url)
    .createHostedBoard(
      CreateHostedBoardIntent(
        intentId: intentId,
        authorDid: widget.did,
        targetForumHost: forumHost.url,
        signature: signature,
        title: title,
        description: result['description'],
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
    );
```

Keep `dart:convert` imported; it is already used in this file.

- [ ] **Step 7: Run app client tests**

Run:

```bash
cd ansible_node/app
flutter test test/relay_discovery_client_test.dart test/forum_host_client_test.dart
```

Expected: tests pass.

- [ ] **Step 8: Commit Task 6**

```bash
git add ansible_node/app/lib/services/relay_discovery_client.dart \
  ansible_node/app/test/relay_discovery_client_test.dart \
  ansible_node/app/lib/services/forum_host_client.dart \
  ansible_node/app/lib/screens/home_shell.dart \
  ansible_node/app/test/forum_host_client_test.dart
git commit -m "Add app relay discovery and signed forum intents"
```

## Task 7: App Web-Session Audience Handling

**Files:**
- Modify: `ansible_node/app/lib/services/web_session_grant_service.dart`
- Modify: `ansible_node/app/lib/services/web_session_approval_client.dart`
- Modify: `ansible_node/app/lib/screens/web_session_approval_screen.dart`
- Modify: `ansible_node/app/test/web_session_grant_service_test.dart`
- Modify: `ansible_node/app/test/web_session_approval_client_test.dart`
- Modify: `ansible_node/app/test/web_session_approval_screen_test.dart`

- [ ] **Step 1: Add failing web-session grant audience test**

Add to `ansible_node/app/test/web_session_grant_service_test.dart`:

```dart
test('canonical web session grant includes audience when present', () {
  final grant = WebSessionGrant(
    challengeId: 'wsc_test',
    relayOrigin: 'https://relay.trisaura.io',
    webOrigin: 'https://trisaura.io',
    audience: 'https://forum.trisaura.io',
    subjectDid: 'did:plc:abc23456789',
    approvingDeviceId: 'app_device_abc',
    scopes: const ['forum:post'],
    expiresAt: DateTime.utc(2026, 6, 2, 12),
    createdAt: DateTime.utc(2026, 6, 2, 11, 45),
  );

  expect(jsonDecode(grant.canonicalJson())['audience'], 'https://forum.trisaura.io');
  expect(grant.toJson()['audience'], 'https://forum.trisaura.io');
});
```

- [ ] **Step 2: Add audience fields in grant and client models**

Modify `WebSessionGrant` constructor and JSON methods in
`ansible_node/app/lib/services/web_session_grant_service.dart`:

```dart
final String? audience;
```

Add `audience` to the constructor and to `toJson()`:

```dart
if (audience != null && audience!.isNotEmpty) 'audience': audience,
```

Add it to `canonicalJson()` before `challenge_id` to preserve sorted order:

```dart
if (audience != null && audience!.isNotEmpty) 'audience': audience,
```

Modify `WebSessionChallenge` and `WebSessionRecord` in
`ansible_node/app/lib/services/web_session_approval_client.dart`:

```dart
final String? audience;
```

Parse:

```dart
audience: json['audience'] as String?,
```

- [ ] **Step 3: Display audience in approval UI**

Modify `ansible_node/app/lib/screens/web_session_approval_screen.dart` where
detail rows are shown:

```dart
if (challenge.audience != null && challenge.audience!.isNotEmpty)
  _DetailRow(label: 'Forum Host', value: challenge.audience!),
```

- [ ] **Step 4: Run web-session app tests**

Run:

```bash
cd ansible_node/app
flutter test test/web_session_grant_service_test.dart \
  test/web_session_approval_client_test.dart \
  test/web_session_approval_screen_test.dart
```

Expected: tests pass after updating expected fixture JSON where canonical grant
strings previously omitted `audience`.

- [ ] **Step 5: Commit Task 7**

```bash
git add ansible_node/app/lib/services/web_session_grant_service.dart \
  ansible_node/app/lib/services/web_session_approval_client.dart \
  ansible_node/app/lib/screens/web_session_approval_screen.dart \
  ansible_node/app/test/web_session_grant_service_test.dart \
  ansible_node/app/test/web_session_approval_client_test.dart \
  ansible_node/app/test/web_session_approval_screen_test.dart
git commit -m "Add forum host audience to web sessions"
```

## Task 8: Distribution Frontend Auth Transport Alignment

**Files:**
- Modify: `ansible_distribution_frontend/src/relay_api_client.mjs`
- Modify: `ansible_distribution_frontend/src/forum_host_client.mjs`
- Modify: `ansible_distribution_frontend/test/relay_api_client.test.mjs`
- Modify: `ansible_distribution_frontend/test/forum_host_client.test.mjs`

- [ ] **Step 1: Add frontend transport assertions**

In `ansible_distribution_frontend/test/forum_host_client.test.mjs`, update the
write test to assert cookie transport:

```js
assert.equal(requests[0].init.credentials, 'same-origin');
assert.equal(requests[0].init.headers.authorization, undefined);
```

In `ansible_distribution_frontend/test/relay_api_client.test.mjs`, add:

```js
test('postJson uses same-origin credentials and no legacy bearer storage', async () => {
  const requests = [];
  const client = createRelayApiClient({
    relayBaseUrl: 'http://localhost:4001',
    storage: { getItem: () => 'legacy-token' },
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return jsonResponse(200, { ok: true });
    },
  });

  await client.postJson(
    '/api/v1/forum-host/web/threads',
    { title: 'Hello' },
    { authenticated: true },
  );

  assert.equal(requests[0].init.credentials, 'same-origin');
  assert.equal(requests[0].init.headers.authorization, undefined);
});
```

- [ ] **Step 2: Run frontend tests**

Run:

```bash
node ansible_distribution_frontend/test/relay_api_client.test.mjs
node ansible_distribution_frontend/test/forum_host_client.test.mjs
```

Expected: tests pass. If the new relay API client test needs the local
`jsonResponse` helper, add it at the bottom of the test file:

```js
function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() {
      return body;
    },
  };
}
```

- [ ] **Step 3: Commit Task 8**

```bash
git add ansible_distribution_frontend/src/relay_api_client.mjs \
  ansible_distribution_frontend/src/forum_host_client.mjs \
  ansible_distribution_frontend/test/relay_api_client.test.mjs \
  ansible_distribution_frontend/test/forum_host_client.test.mjs
git commit -m "Align forum web auth transport"
```

## Task 9: App First-Run Discovery Surface

**Files:**
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
- Modify: `ansible_node/app/lib/screens/sync_settings_screen.dart`
- Modify: `ansible_node/app/test/home_shell_sync_test.dart`
- Modify: `ansible_node/app/test/sync_settings_screen_test.dart`

- [ ] **Step 1: Write failing first-run discovery test**

Add a widget test in `ansible_node/app/test/home_shell_sync_test.dart` that
builds `HomeShell` with no active Forum Host and injects a fake discovery
runner returning one Relay announcement and one starter board. The test should
assert that:

```dart
expect(find.text('Relay online'), findsOneWidget);
expect(find.text('General'), findsOneWidget);
expect(find.text('Start here'), findsOneWidget);
```

Use the existing test fixture setup in `home_shell_sync_test.dart` for database
and DID initialization. Add an optional `relayDiscoveryLoader` constructor
parameter to `HomeShell` so the test can inject the fake result without network
I/O.

- [ ] **Step 2: Add HomeShell discovery loader parameter**

Modify `HomeShell` in `ansible_node/app/lib/screens/home_shell.dart`:

```dart
final Future<RelayDiscovery> Function()? relayDiscoveryLoader;
```

Wire it in the constructor. In `_HomeShellState`, when no active Forum Host or
hosted board exists, call:

```dart
final discovery = await (widget.relayDiscoveryLoader ??
    () => RelayDiscoveryClient(baseUrl: AppEnvironment.defaultRelayBaseUrl).fetchDiscovery())();
```

Store the result in state and render a compact first-run section with Relay
announcements and starter boards. The section must not auto-subscribe and must
not auto-post.

- [ ] **Step 3: Add starter board action**

For each starter board, add a button that opens Sync settings or the existing
Add Elix Relay flow with the discovered `forumHostUrl`. Do not create local
boards directly. The button label should use existing localized Sync wording
where possible.

- [ ] **Step 4: Run first-run tests**

Run:

```bash
cd ansible_node/app
flutter test test/home_shell_sync_test.dart test/sync_settings_screen_test.dart
```

Expected: tests pass and the first-run section appears only when no active Elix
Relay/hosted board is configured.

- [ ] **Step 5: Commit Task 9**

```bash
git add ansible_node/app/lib/screens/home_shell.dart \
  ansible_node/app/lib/screens/sync_settings_screen.dart \
  ansible_node/app/test/home_shell_sync_test.dart \
  ansible_node/app/test/sync_settings_screen_test.dart
git commit -m "Show first-run relay discovery"
```

## Task 10: Full Verification

**Files:**
- No new files.

- [ ] **Step 1: Run Relay tests**

Run:

```bash
cd ansible_relay/phoenix
mix test
```

Expected: all tests pass.

- [ ] **Step 2: Run Flutter tests and analysis**

Run:

```bash
cd ansible_node/app
flutter test
flutter analyze
```

Expected: tests and analyzer pass.

- [ ] **Step 3: Run distribution frontend tests**

Run:

```bash
npm test --prefix ansible_distribution_frontend
```

Expected: frontend tests pass. If this package does not define `npm test`, run
the touched Node tests directly:

```bash
node ansible_distribution_frontend/test/relay_api_client.test.mjs
node ansible_distribution_frontend/test/forum_host_client.test.mjs
```

- [ ] **Step 4: Check staged diff hygiene**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors. `git status --short` may still show unrelated
pre-existing worktree changes, but every file touched by this plan should be
committed or intentionally staged for the next commit.

- [ ] **Step 5: Final implementation summary**

Prepare a summary with:

- New Relay discovery endpoint.
- New Forum Host durable discovery fields.
- App signed-intent write path.
- Web session cookie/audience alignment.
- First-run discovery UI behavior.
- Verification commands and results.

Do not claim production Cloud Run split is complete.
