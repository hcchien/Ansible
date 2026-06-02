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
    field(:owner_kind, :string)
    field(:hosted_board_id, :string)
    field(:title, :string)
    field(:body, :string)
    field(:severity, :string, default: "info")
    field(:locale, :string)
    field(:url, :string)
    field(:starts_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)

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
