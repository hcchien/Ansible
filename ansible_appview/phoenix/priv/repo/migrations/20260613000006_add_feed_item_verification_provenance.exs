defmodule AnsibleAppview.Repo.Migrations.AddFeedItemVerificationProvenance do
  use Ecto.Migration

  # Phase 2 item 1 (SOSP D-1): record *why* a folded item is trusted, not just
  # that it is. `verified_at` stamps when the AppView independently re-verified
  # the Ed25519 signature; `source` records where the op came from (the relay
  # firehose today) so a future second ingest path is auditable; `signature`
  # retains the original signature hex so clients/third parties can re-verify
  # without trusting this projection. `anchor_expires_at` carries the author
  # DID anchor's expiry when the firehose supplies it (TODO: relay delta does
  # not carry it yet — see Folder).
  def change do
    alter table(:feed_items) do
      add(:source, :string, null: false, default: "relay_firehose")
      add(:verified_at, :utc_datetime_usec)
      add(:signature, :text)
      add(:anchor_expires_at, :utc_datetime_usec)
    end
  end
end
