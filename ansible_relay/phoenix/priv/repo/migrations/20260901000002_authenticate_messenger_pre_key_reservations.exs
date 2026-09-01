defmodule AnsibleRelay.Repo.Migrations.AuthenticateMessengerPreKeyReservations do
  use Ecto.Migration

  def change do
    alter table(:messenger_pre_keys) do
      add(:reserved_by_did, :string)
      add(:reserved_by_device_id, :string)
      add(:reservation_request_id, :string)
    end

    create(
      unique_index(
        :messenger_pre_keys,
        [
          :subject_did,
          :device_id,
          :reserved_by_did,
          :reserved_by_device_id,
          :reservation_request_id
        ],
        name: :messenger_pre_keys_request_reservation_index,
        where: "reservation_request_id IS NOT NULL"
      )
    )
  end
end
