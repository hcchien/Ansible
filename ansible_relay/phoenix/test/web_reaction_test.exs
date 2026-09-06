defmodule AnsibleRelay.WebReactionTest do
  use ExUnit.Case, async: false
  alias AnsibleRelay.{Repo, OpStore, WebPublication}
  alias AnsibleRelay.Db.ForumHostBoard
  alias AnsibleRelay.ForumHost.Store

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    board =
      Repo.insert!(%ForumHostBoard{
        hosted_board_id: "reaction-board-#{System.unique_integer([:positive])}",
        slug: "reaction-#{System.unique_integer([:positive])}",
        canonical_board_uri:
          "https://example.test/reactions/#{System.unique_integer([:positive])}",
        title: "Reactions"
      })

    %{board: to_string(board.board_id)}
  end

  defp operation(board, action, payload, extra \\ %{}) do
    now = DateTime.utc_now()

    Map.merge(
      %{
        "type" => "io.trisaura.webPublicationOperation",
        "version" => 1,
        "operation_id" => "web-reaction-#{System.unique_integer([:positive])}",
        "author_did" => "did:test:alice",
        "action" => action,
        "target_forum_host" => Store.base_url(),
        "board_id" => board,
        "entity_type" => "reaction",
        "entity_id" => "reaction-1",
        "parent_id" => "reply-1",
        "visibility" => "public",
        "federate" => false,
        "board_policy_version" => 1,
        "payload" => payload,
        "payload_hash" => hash(payload),
        "nonce" => "nonce",
        "created_at" => DateTime.to_iso8601(now),
        "expires_at" => DateTime.to_iso8601(DateTime.add(now, 60, :second))
      },
      extra
    )
  end

  defp hash(value),
    do: :crypto.hash(:sha256, WebPublication.canonical_json(value)) |> Base.encode16(case: :lower)

  defp validate(op, did \\ "did:test:alice") do
    WebPublication.validate_operation(
      %{subject_did: did, scopes: ~w(forum:react forum:edit forum:delete)},
      op,
      hash(op)
    )
  end

  test "signed reactions allow all four types for posts and threads", %{board: board} do
    for target <- ~w(post thread), type <- ~w(thumbsUp happy sad angry) do
      op =
        operation(board, "forum.react", %{
          "targetType" => target,
          "targetId" => "reply-1",
          "reactionType" => type
        })

      assert {:ok, ^op, _, _} = validate(op)
    end

    legacy = operation(board, "forum.react", %{"reactionType" => "happy"})
    assert {:ok, ^legacy, _, _} = validate(legacy)

    invalid =
      operation(board, "forum.react", %{"targetType" => "wallet", "reactionType" => "happy"})

    assert {:error, :invalid_operation} = validate(invalid)
    invalid = operation(board, "forum.react", %{"reactionType" => "unknown"})
    assert {:error, :invalid_operation} = validate(invalid)
  end

  test "edit and removal preserve author target board and revision", %{board: board} do
    payload = %{
      "targetType" => "post",
      "targetId" => "reply-1",
      "reactionType" => "happy",
      "boardId" => board
    }

    assert {:ok, _} =
             OpStore.append_reaction_insert(
               %{
                 op_id: "original",
                 author_did: "did:test:alice",
                 entity_type: "reaction",
                 entity_id: "reaction-1",
                 op_type: "insert",
                 signature: "fixture",
                 payload: payload |> Jason.encode!() |> Base.encode64()
               },
               "post",
               "reply-1"
             )

    edit =
      operation(board, "forum.edit", Map.put(payload, "reactionType", "sad"), %{
        "expected_previous_revision" => "original"
      })

    assert {:ok, ^edit, _, _} = validate(edit)

    remove =
      operation(board, "forum.delete", Map.delete(payload, "reactionType"), %{
        "expected_previous_revision" => "original"
      })

    assert {:ok, ^remove, _, _} = validate(remove)

    retarget =
      operation(board, "forum.edit", Map.put(payload, "targetId", "other"), %{
        "expected_previous_revision" => "original"
      })

    assert {:error, :invalid_operation} = validate(retarget)
    foreign = Map.put(edit, "author_did", "did:test:bob")
    assert {:error, :not_original_author} = validate(foreign, "did:test:bob")
    assert {:error, :invalid_operation} = validate(Map.delete(edit, "expected_previous_revision"))
  end
end
