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
      |> Map.put(
        "canonical_board_uri",
        Map.get(attrs, "canonical_board_uri", "#{base_url()}/boards/#{slug}")
      )

    %ForumHostBoard{}
    |> ForumHostBoard.changeset(changes)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
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
      on_conflict:
        {:replace,
         [
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

  defp maybe_owner(query, owner_kind) do
    where(query, [announcement], announcement.owner_kind == ^owner_kind)
  end

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
    if Repo.get_by(ForumHostBoard, slug: slug) do
      "#{slug}-#{System.unique_integer([:positive])}"
    else
      slug
    end
  end

  defp payload_hash(attrs) do
    attrs
    |> Map.take([:intent_id, :author_did, :title, :description])
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
