defmodule AnsibleAppview.ForumHostBoardRegistryTest do
  use ExUnit.Case, async: true

  alias AnsibleAppview.ForumHostBoardRegistry

  @contract_cases Path.expand(
                    "../../contracts/identity-resolution/v1/conformance/board-resolution.json",
                    File.cwd!()
                  )
                  |> File.read!()
                  |> Jason.decode!()

  @boards [
    %{
      "board_id" => 2,
      "hosted_board_id" => "2026",
      "slug" => "2026-election"
    }
  ]

  test "resolves the legacy hosted id from the canonical numeric id" do
    assert ForumHostBoardRegistry.resolve_legacy_hosted_board_id(@boards, "2") == "2026"
  end

  test "resolves the legacy hosted id from the hosted id or slug used by web routes" do
    assert ForumHostBoardRegistry.resolve_legacy_hosted_board_id(@boards, "2026") == "2026"

    assert ForumHostBoardRegistry.resolve_legacy_hosted_board_id(@boards, "2026-election") ==
             "2026"
  end

  test "matches shared board identity cases through the existing registry" do
    for test_case <- @contract_cases do
      board = hd(test_case["boards"])

      hosted_board = %{
        "board_id" => String.to_integer(board["id"]),
        "hosted_board_id" => List.first(board["legacy_ids"]) || board["slug"],
        "slug" => board["slug"]
      }

      result =
        ForumHostBoardRegistry.resolve_legacy_hosted_board_id(
          [hosted_board],
          test_case["reference"]
        )

      expected =
        if test_case["expected_id"],
          do: hosted_board["hosted_board_id"],
          else: nil

      assert result == expected, test_case["name"]
    end
  end
end
