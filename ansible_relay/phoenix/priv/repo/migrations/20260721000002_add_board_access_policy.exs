defmodule AnsibleRelay.Repo.Migrations.AddBoardAccessPolicy do
  use Ecto.Migration

  def change do
    alter table(:forum_host_boards) do
      add(:access_policy, :map,
        null: false,
        default: %{
          "version" => 1,
          "discovery" => "public",
          "read" => %{"requirement" => "public"},
          "post" => %{"requirement" => "posting_policy"},
          "requirements" => %{},
          "capability_ttl_seconds" => 300,
          "content_visibility" => "public",
          "federation" => "enabled"
        }
      )

      add(:access_policy_version, :bigint, null: false, default: 1)
      add(:content_visibility, :string, null: false, default: "public")
      add(:federation_policy, :map, null: false, default: %{"mode" => "enabled"})
    end

    create(
      constraint(:forum_host_boards, :access_policy_version_positive,
        check: "access_policy_version > 0"
      )
    )

    create(
      constraint(:forum_host_boards, :content_visibility_known,
        check: "content_visibility IN ('public', 'host_visible', 'end_to_end_encrypted')"
      )
    )
  end
end
