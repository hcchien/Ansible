defmodule AnsibleAppview.Ingest.Folder do
  @moduledoc """
  Folds relay ops into the `feed_items` projection. Re-verifies every op's
  Ed25519 signature (double verification) and only indexes public/unlisted
  content. Idempotent by `log_id`, so re-folding an overlapping range is safe.
  """

  alias AnsibleAppview.{Repo, SigVerifier, SigningPayload}
  alias AnsibleAppview.Db.FeedItem

  @content_types ~w(murmur note)
  @relayable ~w(public unlisted)

  @doc "Folds a list of relay op maps. Returns {indexed_count, max_log_id}."
  @spec apply_ops([map()]) :: {non_neg_integer(), integer() | nil}
  def apply_ops(ops) when is_list(ops) do
    # Ed25519 verification is CPU-bound and independent per op, so verify the
    # whole page in parallel across schedulers before the sequential DB upserts.
    prepared =
      ops
      |> Task.async_stream(
        fn op -> {op, decode_payload(op["payload"]), verify(op)} end,
        max_concurrency: System.schedulers_online(),
        ordered: true,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    max_log =
      Enum.reduce(prepared, nil, fn {op, _payload, _ok?}, acc ->
        max_int(acc, op["log_id"])
      end)

    rows =
      prepared
      |> Enum.filter(fn {op, payload, verified?} ->
        verified? and visibility_ok?(op["entity_type"], payload)
      end)
      |> Enum.map(fn {op, payload, _} -> row(op, payload) end)
      # Same log_id can appear once per page; keep the last occurrence.
      |> Enum.uniq_by(& &1.log_id)

    indexed =
      case rows do
        [] ->
          0

        _ ->
          {count, _} =
            Repo.insert_all(FeedItem, rows,
              on_conflict: {:replace_all_except, [:inserted_at]},
              conflict_target: :log_id
            )

          count
      end

    {indexed, max_log}
  end

  defp verify(op) do
    pk = op["public_key_hex"]
    sig = op["signature"]

    is_binary(pk) and is_binary(sig) and
      SigVerifier.verify_ed25519(pk, SigningPayload.build(op), sig)
  end

  defp visibility_ok?(entity_type, payload) when entity_type in @content_types do
    case payload do
      %{"visibility" => v} when is_binary(v) -> v in @relayable
      # murmur has no visibility field; note requires one.
      _ -> entity_type == "murmur"
    end
  end

  defp visibility_ok?(_entity_type, _payload), do: true

  defp row(op, payload) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %{
      log_id: op["log_id"],
      op_id: op["op_id"],
      author_did: op["author_did"],
      entity_type: op["entity_type"],
      entity_id: op["entity_id"],
      op_type: op["op_type"],
      board_id: payload["boardId"],
      thread_id: payload["threadId"],
      visibility: payload["visibility"],
      item_created_at:
        parse_dt(payload["publishedAt"] || payload["createdAt"] || op["received_at"]),
      payload: payload,
      public_key_hex: op["public_key_hex"],
      author_tier: op["reputation_tier"] || "basic",
      deleted: op["op_type"] == "delete",
      sig_verified: true,
      inserted_at: now,
      updated_at: now
    }
  end

  defp decode_payload(payload) when is_map(payload), do: payload

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = map} ->
        map

      _ ->
        case Base.decode64(payload) do
          {:ok, raw} ->
            case Jason.decode(raw) do
              {:ok, %{} = map} -> map
              _ -> %{}
            end

          :error ->
            %{}
        end
    end
  end

  defp decode_payload(_), do: %{}

  defp parse_dt(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      # insert_all requires usec precision for :utc_datetime_usec columns, so
      # force the microsecond precision to 6 (from_iso8601 may yield precision 0).
      {:ok, dt, _} -> %{dt | microsecond: {elem(dt.microsecond, 0), 6}}
      _ -> nil
    end
  end

  defp parse_dt(_), do: nil

  defp max_int(nil, b), do: b
  defp max_int(a, nil), do: a
  defp max_int(a, b), do: max(a, b)
end
