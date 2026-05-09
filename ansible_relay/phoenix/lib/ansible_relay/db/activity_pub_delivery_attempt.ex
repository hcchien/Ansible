defmodule AnsibleRelay.Db.ActivityPubDeliveryAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "activity_pub_delivery_attempts" do
    field(:publication_id, :string)
    field(:remote_inbox, :string)
    field(:activity_id, :string)
    field(:activity_type, :string)
    field(:payload, :map)
    field(:status, :string)
    field(:attempt_count, :integer, default: 0)
    field(:last_attempt_at, :utc_datetime_usec)
    field(:next_retry_at, :utc_datetime_usec)
    field(:last_error, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :publication_id,
      :remote_inbox,
      :activity_id,
      :activity_type,
      :payload,
      :status,
      :attempt_count,
      :last_attempt_at,
      :next_retry_at,
      :last_error
    ])
    |> validate_required([
      :publication_id,
      :remote_inbox,
      :activity_id,
      :activity_type,
      :payload,
      :status
    ])
    |> unique_constraint([:publication_id, :remote_inbox],
      name: :activity_pub_delivery_attempts_publication_inbox_index
    )
  end
end
