defmodule AnsibleRelay.Identity.AttestationStore do
  @moduledoc """
  Portable issuer re-verification layer (federation trust hole follow-up to
  the app's fail-closed fix): after `/api/v2/reputation/present` accepts a
  VP, the issuer-signed VC that earned the tier is persisted here and served
  at `GET /api/v1/identity/attestation/:did`.

  The point is that consumers re-verify the ISSUER's Ed25519 proof
  themselves (against their own pinned issuer trust registry) — the relay
  serving this is a cache/availability layer, never the trust root. A
  malicious relay can withhold an attestation (denial → fail closed to
  `basic`) but cannot forge one.
  """

  import Ecto.Query

  alias AnsibleRelay.{Db.DidAttestation, Repo}

  @doc "Persist (upsert) the accepted VC for a DID."
  def put(did, credential_type, reputation_tier, vc)
      when is_binary(did) and is_map(vc) do
    %DidAttestation{}
    |> DidAttestation.changeset(%{
      did: did,
      credential_type: credential_type,
      reputation_tier: reputation_tier,
      vc: vc,
      presented_at: DateTime.utc_now()
    })
    |> Repo.insert(
      on_conflict: {:replace, [:credential_type, :reputation_tier, :vc, :presented_at, :updated_at]},
      conflict_target: :did
    )
    |> case do
      {:ok, _row} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "The stored attestation for a DID, or nil."
  def get(did) when is_binary(did) do
    Repo.one(from(a in DidAttestation, where: a.did == ^did))
  end
end
