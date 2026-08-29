defmodule AnsibleRelay.ForumHost.DeliberationsTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Db.ForumHostBoard
  alias AnsibleRelay.ForumHost.{BoardAccessPolicy, Deliberations}
  alias AnsibleRelay.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Application.get_env(:ansible_relay, :sync_capability_secret)
    Application.put_env(:ansible_relay, :sync_capability_secret, "deliberation-test-secret")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ansible_relay, :sync_capability_secret, previous),
        else: Application.delete_env(:ansible_relay, :sync_capability_secret)
    end)

    {:ok, board: insert_board()}
  end

  test "multi-statement detail reports aggregates and only returns the viewer's own response", %{
    board: board
  } do
    {:ok, deliberation} = create_deliberation(board, "aggregates_only")

    assert {:ok, statement} =
             Deliberations.submit_statement(
               board,
               deliberation.id,
               "  Ship a small version every week.  ",
               "did:example:alice",
               "statement-1"
             )

    assert statement.text == "Ship a small version every week."

    assert {:ok, response} =
             Deliberations.cast_vote(
               board,
               deliberation.id,
               statement.id,
               "agree",
               "did:example:alice",
               "vote-1",
               nil
             )

    assert response.stance == "agree"

    assert {:error, :stale_vote_intent} =
             Deliberations.cast_vote(
               board,
               deliberation.id,
               statement.id,
               "disagree",
               "did:example:alice",
               "vote-stale",
               nil
             )

    assert {:ok, viewer} =
             Deliberations.viewer_responses(board, deliberation.id, "did:example:alice")

    assert viewer[statement.id] == %{stance: "agree", last_intent_id: "vote-1"}

    assert {:ok, detail} = Deliberations.detail(board, deliberation.id)
    refute inspect(detail) =~ "did:example:alice"
    assert detail.report.participant_count == 1

    assert detail.report.statement_aggregates |> hd() |> Map.take([:agree, :disagree, :pass]) ==
             %{agree: 1, disagree: 0, pass: 0}

    assert {:ok, first_report} = Deliberations.report(board, deliberation.id)
    assert {:ok, repeated_report} = Deliberations.report(board, deliberation.id)
    assert repeated_report.snapshot_id == first_report.snapshot_id
    assert repeated_report.generated_at == first_report.generated_at
  end

  test "matrix exports require the threshold and re-key pseudonyms for every export", %{
    board: board
  } do
    {:ok, deliberation} = create_deliberation(board, "pseudonymous_matrix")

    {:ok, statement} =
      Deliberations.submit_statement(
        board,
        deliberation.id,
        "Ship a small version every week.",
        "did:example:author",
        "statement-matrix"
      )

    assert {:error, :insufficient_export_participants} =
             Deliberations.export(board, deliberation.id, "pseudonymous_matrix")

    for number <- 1..5 do
      assert {:ok, _} =
               Deliberations.cast_vote(
                 board,
                 deliberation.id,
                 statement.id,
                 if(rem(number, 2) == 0, do: "disagree", else: "agree"),
                 "did:example:participant-#{number}",
                 "vote-matrix-#{number}",
                 nil
               )
    end

    assert {:ok, aggregates} = Deliberations.export(board, deliberation.id, "aggregates")
    refute Map.has_key?(aggregates, :responses)

    assert {:ok, first} = Deliberations.export(board, deliberation.id, "pseudonymous_matrix")
    assert {:ok, second} = Deliberations.export(board, deliberation.id, "pseudonymous_matrix")
    assert length(first.responses) == 5
    refute inspect(first.responses) =~ "did:example:"

    first_ids = first.responses |> Enum.map(& &1.export_participant_id) |> MapSet.new()
    second_ids = second.responses |> Enum.map(& &1.export_participant_id) |> MapSet.new()
    assert MapSet.disjoint?(first_ids, second_ids)
    assert first.manifest.dataset_digest == second.manifest.dataset_digest
  end

  defp create_deliberation(board, export_mode) do
    Deliberations.create(
      board,
      %{
        "title" => "  Release cadence  ",
        "prompt" => "How should this board balance speed and reliability?",
        "export_mode" => export_mode,
        "min_report_participants" => 5,
        "min_group_size" => 3,
        "unknown_client_field" => "ignored"
      },
      "did:example:creator",
      "create-#{export_mode}"
    )
  end

  defp insert_board do
    Repo.insert!(%ForumHostBoard{
      hosted_board_id: "deliberation-board",
      slug: "deliberation-board",
      canonical_board_uri: "https://relay.example/boards/deliberation-board",
      title: "Deliberation Board",
      access_policy: BoardAccessPolicy.default(2),
      access_policy_version: 2,
      content_visibility: "public",
      federation_policy: %{"mode" => "enabled"}
    })
  end
end
