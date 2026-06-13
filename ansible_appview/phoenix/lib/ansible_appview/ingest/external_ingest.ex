defmodule AnsibleAppview.Ingest.ExternalIngest do
  @moduledoc """
  Pull ingest for curated inbound ActivityPub content (design 2026-06-13).

  For one enabled `ExternalSource`, fetches the actor's public outbox, normalizes
  each public Note to an internal external-item, and writes `feed_items` rows in
  the **external lane**:

    * `source = "activitypub"`
    * `sig_verified = false`  — foreign content has no Elix op/signature, so it can
      never be verified; this is what keeps it OUT of every Phase 2 verified read
      (`timeline.ex` / `discovery.ex` all require `sig_verified == true`).
    * `author_tier = "external_unverified"`
    * `external_actor_uri` / `external_instance` / `compliance_level` set
    * `op_id = <AP object id>` — the dedup key. The unique index on `op_id` plus
      `on_conflict: :nothing` means re-polling the same item never duplicates it.

  HTTP-signature validity is *recorded* (`HttpSignature.status/1`) for audit but
  is transport auth, never Elix identity — it never flips `sig_verified`.

  Failure tolerance: a fetch error for one source returns `{:error, reason}` and
  is counted in `external_source_fetch_errors_total`; it never raises, so the
  poller and the native firehose ingest are unaffected.

  These rows are off every verified surface. They become *readable* only via the
  per-board external read endpoint (`AnsibleAppview.External` / Task 4b-1):
  `GET /api/v1/boards/:board_id/external`, scoped by the source's mapped
  `board_id`. Whether that lane is *shown* is gated upstream by the per-board
  `external_inclusion` policy (relay forum-host) AND the per-user opt-in filter —
  the AppView serves the lane; the board/user gating lives at the relay policy +
  client (design D4). External content never reaches verified/真人版 surfaces.
  """

  require Logger

  alias AnsibleAppview.{ExternalSources, Metrics, Repo}
  alias AnsibleAppview.Db.{ExternalSource, FeedItem}
  alias AnsibleAppview.Ingest.External.{Note, OutboxClient}

  @source "activitypub"
  @author_tier "external_unverified"

  @doc """
  Ingest one curated source by actor URI or struct. Tests call this directly so
  they do not depend on the poller's timing.

  Returns `{:ok, %{ingested: n, deduped: n, http_sig: %{...}}}` on a successful
  fetch (even if it yields zero items), or `{:error, reason}` if the fetch failed
  (tolerated — never raised).
  """
  @spec ingest_source(ExternalSource.t() | String.t()) :: {:ok, map()} | {:error, term()}
  def ingest_source(%ExternalSource{enabled: false}), do: {:ok, %{ingested: 0, deduped: 0}}

  def ingest_source(%ExternalSource{} = source) do
    do_ingest(source)
  end

  def ingest_source(actor_uri) when is_binary(actor_uri) do
    case ExternalSources.get_by_actor_uri(actor_uri) do
      nil -> {:error, :unknown_source}
      %ExternalSource{} = source -> ingest_source(source)
    end
  end

  defp do_ingest(%ExternalSource{} = source) do
    case OutboxClient.impl().fetch_outbox(source.actor_uri) do
      {:ok, raw_items} when is_list(raw_items) ->
        result = fold_items(source, raw_items)
        ExternalSources.mark_polled(source.actor_uri)
        {:ok, result}

      {:error, reason} = err ->
        Metrics.inc("external_source_fetch_errors_total", %{instance: source.instance})
        Logger.warning("external ingest fetch failed for #{source.actor_uri}: #{inspect(reason)}")
        err
    end
  rescue
    # A malformed source must never crash the poller or affect native ingest.
    error ->
      Metrics.inc("external_source_fetch_errors_total", %{instance: source.instance})
      Logger.warning("external ingest crashed for #{source.actor_uri}: #{inspect(error)}")
      {:error, {:exception, error.__struct__}}
  end

  defp fold_items(%ExternalSource{} = source, raw_items) do
    normalized =
      raw_items
      |> Enum.map(&Note.normalize(&1, source.actor_uri))
      |> Enum.flat_map(fn
        {:ok, item} -> [item]
        :skip -> []
      end)
      # Same object can appear once per fetch; keep the first.
      |> Enum.uniq_by(& &1.object_id)

    rows = Enum.map(normalized, &row(source, &1))

    inserted =
      case rows do
        [] ->
          0

        _ ->
          # Dedup on AP object id: on_conflict :nothing + the op_id unique index
          # means a re-poll of the same item inserts nothing.
          {count, _} =
            Repo.insert_all(FeedItem, rows, on_conflict: :nothing, conflict_target: :op_id)

          count
      end

    attempted = length(rows)
    deduped = attempted - inserted

    if inserted > 0 do
      Metrics.inc("external_ingest_total", %{instance: source.instance}, inserted)
    end

    if deduped > 0 do
      Metrics.inc("external_ingest_dedup_total", %{}, deduped)
    end

    %{ingested: inserted, deduped: deduped, attempted: attempted}
  end

  defp row(%ExternalSource{} = source, item) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %{
      # Synthetic, unique, always-negative log_id (never collides with positive
      # relay log_ids). nextval is fetched per row inside the insert.
      log_id: next_external_log_id(),
      op_id: item.object_id,
      author_did: item.actor_uri,
      entity_type: "note",
      entity_id: item.object_id,
      op_type: "insert",
      # Stamp the source's mapped Elix board onto the row (design D4, Task 4b-1)
      # so the per-board external read is a simple (board_id, source) filter.
      # NULL when the source is ingested but not surfaced to any board — still off
      # all verified reads via sig_verified=false.
      board_id: source.board_id,
      thread_id: nil,
      visibility: "public",
      item_created_at: parse_dt(item.published_at) || now,
      payload: %{
        "type" => "external_note",
        "content" => item.content,
        "name" => item.name,
        "http_signature_status" => Atom.to_string(item.http_signature_status)
      },
      public_key_hex: nil,
      author_tier: @author_tier,
      deleted: false,
      # THE INVARIANT: external content is never verified. This is what keeps it
      # out of every Phase 2 verified read by construction.
      sig_verified: false,
      source: @source,
      verified_at: nil,
      signature: nil,
      anchor_expires_at: nil,
      external_actor_uri: item.actor_uri,
      external_instance: item.instance,
      compliance_level: source.compliance_level,
      inserted_at: now,
      updated_at: now
    }
  end

  # Pull one value from the dedicated negative sequence created in the migration.
  defp next_external_log_id do
    %{rows: [[id]]} = Repo.query!("SELECT nextval('external_feed_log_seq')")
    id
  end

  defp parse_dt(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> %{dt | microsecond: {elem(dt.microsecond, 0), 6}}
      _ -> nil
    end
  end

  defp parse_dt(_), do: nil
end
