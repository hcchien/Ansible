defmodule AnsibleRelay.Authority.PublicStatus do
  @moduledoc """
  Minimal current Relay status for an already-public operation. Completeness and
  receipt ordering are Relay assertions, not independent witness guarantees.
  No credential list or private credential fields are published.
  """
  import Ecto.Query
  alias AnsibleRelay.{Repo, Db.WebauthnCredential}

  def for_operation(op, chain) do
    %{
      version: 1,
      superseded: superseded?(op),
      did: op.author_did,
      state:
        if(
          chain != [] or
            (String.starts_with?(op.author_did, "did:key:") and
               not AnsibleRelay.Identity.AnchorStore.frozen?(op.author_did)),
          do: "active",
          else: "unavailable"
        ),
      checked_at: DateTime.to_iso8601(DateTime.utc_now()),
      credential: credential_status(op)
    }
  end

  # Prevent late retries from restoring an older edit, profile or follow after a
  # newer mutation/deletion. This is a projection hint, never an author proof.
  defp superseded?(%{log_id: log} = op) when is_integer(log) do
    Repo.exists?(
      from(o in AnsibleRelay.Db.Op,
        where:
          o.author_did == ^op.author_did and o.entity_type == ^op.entity_type and
            o.entity_id == ^op.entity_id and o.id > ^log
      )
    )
  end

  defp superseded?(_), do: false

  defp credential_status(op) do
    with {:ok, bytes} <- Base.decode64(op.payload),
         {:ok, %{"web_author_proof" => proof}} when is_map(proof) <- Jason.decode(bytes),
         id when is_binary(id) <- proof["credential_id"],
         {:ok, raw_id} <- Base.url_decode64(id, padding: false) do
      hash = :crypto.hash(:sha256, raw_id) |> Base.encode16(case: :lower)

      case Repo.get(WebauthnCredential, raw_id) do
        %WebauthnCredential{did: did, revoked_at: at} when did == op.author_did ->
          %{
            credential_hash: hash,
            state: if(at, do: "revoked", else: "active"),
            revoked_at: at && DateTime.to_iso8601(at)
          }

        _ ->
          %{credential_hash: hash, state: "unknown"}
      end
    else
      _ -> nil
    end
  end
end
