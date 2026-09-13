defmodule AnsibleAppview.Authority.Pending do
  @moduledoc "Bounded durable retries of exact public Relay records; no duplicate content store."
  alias AnsibleAppview.{Repo, Authority.Witness}
  alias AnsibleAppview.Ingest.{Folder, RelayClient}

  def retry_due(base, fetch \\ &RelayClient.fetch_delta/3) do
    rows =
      Repo.query!(
        "SELECT did,op_id,digest,log_id,attempts FROM authority_pending WHERE next_retry_at <= $1 ORDER BY next_retry_at,log_id LIMIT 5",
        [DateTime.utc_now()]
      ).rows

    Enum.reduce(rows, 0, fn [did, id, digest, log, attempts], count ->
      # Schedule before network IO so a restart/error cannot hammer one record.
      delay = min(3600, trunc(15 * :math.pow(2, min(attempts, 8))))

      Repo.query!(
        "UPDATE authority_pending SET attempts=attempts+1,next_retry_at=$3 WHERE did=$1 AND op_id=$2",
        [did, id, DateTime.add(DateTime.utc_now(), delay)]
      )

      count + retry_one(base, fetch, did, id, digest, log)
    end)
  end

  defp retry_one(base, fetch, did, id, digest, log) do
    with {:ok, %{ops: ops}} <- fetch.(base, log - 1, 1),
         op when is_map(op) <-
           Enum.find(
             ops,
             &(&1["log_id"] == log and &1["op_id"] == id and &1["author_did"] == did)
           ),
         true <- Witness.operation_digest(op) == digest do
      {indexed, _} = Folder.apply_ops([op], authority_source: :relay)
      indexed
    else
      _ -> 0
    end
  rescue
    _ -> 0
  end
end
