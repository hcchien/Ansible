defmodule AnsibleAppview.ForumHostBoardRegistryTest do
  use ExUnit.Case, async: true

  alias AnsibleAppview.ForumHostBoardRegistry

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
end
