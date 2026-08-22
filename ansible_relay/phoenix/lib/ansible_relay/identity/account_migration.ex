defmodule AnsibleRelay.Identity.AccountMigration do
  @moduledoc """
  Atomically records a verified migration and makes it visible to alias-aware
  read models.

  The durable legacy account, assurance, recovery, and historical signed rows
  are intentionally retained. `DidAccountCache` and `IdentityCache` project
  their public routing/trust state onto the v1 DID after this evidence commits.
  This avoids irreversible bulk rewrites and preserves signature provenance.
  """

  import Ecto.Query

  alias AnsibleRelay.{DidAccountCache, IdentityCache, Repo}

  alias AnsibleRelay.Db.{
    DidAccount,
    DidElixMigration,
    IdentityRecoveryAuditEvent
  }

  def complete(params, legacy_anchor, v1_anchor, canonical_body, created_at) do
    legacy_did = params["legacy_did"]
    v1_did = params["v1_did"]
    now = DateTime.utc_now()

    result =
      Repo.transaction(fn ->
        lock_identity_rows(legacy_did, v1_did)

        case Repo.get(DidElixMigration, legacy_did) do
          %DidElixMigration{} = existing ->
            if existing.v1_did == v1_did and existing.canonical_body == canonical_body,
              do: {:existing, existing},
              else: Repo.rollback(:conflict)

          nil ->
            legacy_account =
              Repo.one(from(a in DidAccount, where: a.did == ^legacy_did, lock: "FOR UPDATE"))

            v1_account =
              Repo.one(from(a in DidAccount, where: a.did == ^v1_did, lock: "FOR UPDATE"))

            validate_account_projection!(
              legacy_account,
              v1_account,
              legacy_anchor,
              v1_anchor
            )

            row =
              %DidElixMigration{}
              |> DidElixMigration.changeset(%{
                legacy_did: legacy_did,
                v1_did: v1_did,
                handle: legacy_anchor.handle,
                state: "completed",
                canonical_body: canonical_body,
                legacy_sig: params["legacy_sig"],
                v1_sig: params["v1_sig"],
                created_at: created_at,
                completed_at: now
              })
              |> insert_or_rollback!()

            %IdentityRecoveryAuditEvent{}
            |> IdentityRecoveryAuditEvent.changeset(%{
              did: v1_did,
              event_type: "identity_migrated",
              reason_code: "user_dual_signed",
              anchor_cid: v1_anchor.anchor_cid,
              metadata: %{
                "legacy_did" => legacy_did,
                "recovery_codes_reset_required" => true
              }
            })
            |> insert_or_rollback!()

            {:created, row}
        end
      end)

    case result do
      {:ok, {disposition, row}} ->
        invalidate_caches(legacy_did, v1_did, legacy_anchor.handle)
        {:ok, disposition, row}

      {:error, %Ecto.Changeset{}} ->
        {:error, :conflict}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp lock_identity_rows(legacy_did, v1_did) do
    [legacy_did, v1_did]
    |> Enum.sort()
    |> Enum.each(fn did ->
      Repo.one(
        from(a in AnsibleRelay.Db.IdentityAnchor,
          where: a.did == ^did and a.state == "active",
          lock: "FOR UPDATE"
        )
      ) || Repo.rollback(:did_not_found)
    end)
  end

  defp validate_account_projection!(nil, _v1_account, _legacy_anchor, _v1_anchor),
    do: Repo.rollback(:account_not_found)

  defp validate_account_projection!(legacy, v1_account, legacy_anchor, v1_anchor) do
    legacy_algorithm = legacy.signing_algorithm || "ed25519"
    anchor_algorithm = legacy_anchor.identity_key_algorithm || "ed25519"

    cond do
      legacy.handle != legacy_anchor.handle or legacy.handle != v1_anchor.handle ->
        Repo.rollback(:handle_mismatch)

      legacy.public_key_hex != legacy_anchor.identity_key or legacy_algorithm != anchor_algorithm ->
        Repo.rollback(:account_state_mismatch)

      v1_account != nil and
          (v1_account.handle != legacy.handle or
             v1_account.public_key_hex != v1_anchor.identity_key) ->
        Repo.rollback(:account_state_mismatch)

      true ->
        :ok
    end
  end

  defp insert_or_rollback!(changeset) do
    case Repo.insert(changeset) do
      {:ok, row} -> row
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp invalidate_caches(legacy_did, v1_did, handle) do
    DidAccountCache.invalidate(legacy_did, handle)
    DidAccountCache.invalidate(v1_did, handle)
    IdentityCache.invalidate(legacy_did)
    IdentityCache.invalidate(v1_did)
    :ok
  end
end
