defmodule AnsibleRelay.CommunityNotes.Store do
  @moduledoc """
  Private rating storage and transparent aggregate scoring for Community Notes.

  Individual ratings remain inside the Forum Host boundary. Public results
  contain only counts, reason tags, scorer provenance, and an input commitment.
  """

  import Ecto.Query

  alias AnsibleRelay.{DidAccountCache, OpStore, Repo}
  alias AnsibleRelay.CommunityNotes.RateLimiter
  alias AnsibleRelay.Db.ForumHostContextNoteRating
  alias AnsibleRelay.ForumHost.Moderation
  alias AnsibleRelay.Identity.MigrationStore

  @scorer_id "elix_host_consensus"
  @scorer_version 1
  @helpful_tags ~w(addresses_claim important_context good_sources clear)
  @not_helpful_tags ~w(incorrect sources_missing_or_unreliable off_topic opinion_or_speculation argumentative_or_harassing outdated)
  @critical_tags ~w(incorrect sources_missing_or_unreliable)
  @level_values %{"helpful" => 1.0, "somewhat_helpful" => 0.5, "not_helpful" => 0.0}

  def helpful_tags, do: @helpful_tags
  def not_helpful_tags, do: @not_helpful_tags
  def allowed_tags, do: @helpful_tags ++ @not_helpful_tags

  @doc "Store or replace one private rating after a signed-intent verification."
  def rate(attrs) do
    with {:ok, note} <- note_snapshot(attrs.note_id),
         :ok <- reject_self_rating(note.author_did, attrs.rater_did),
         nil <- rating_by_intent(attrs.intent_id),
         :ok <- RateLimiter.check_rater(attrs.rater_did) do
      persist_rating(note, attrs)
    else
      %ForumHostContextNoteRating{} = existing -> {:ok, :duplicate, public_rating(existing)}
      {:error, _reason, _detail} = error -> error
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Return a privacy-safe aggregate status for one context note."
  def status(note_id) when is_binary(note_id) do
    with {:ok, note} <- note_snapshot(note_id) do
      {:ok, score(note)}
    end
  end

  @doc "Return aggregate statuses for every context note targeting one entity id."
  def statuses_for_target(target_ref) when is_binary(target_ref) do
    statuses =
      target_ref
      |> OpStore.context_note_ids_for_target()
      |> Enum.map(&status/1)
      |> Enum.flat_map(fn
        {:ok, result} -> [result]
        _ -> []
      end)

    {:ok, statuses}
  end

  defp persist_rating(note, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    rater_key = rater_key(attrs.rater_did)

    rating_attrs = %{
      note_id: note.note_id,
      target_ref: note.payload["targetEntityId"],
      board_id: note.payload["boardId"] || note.payload["board_id"],
      rater_did: attrs.rater_did,
      rater_key: rater_key,
      rater_tier: DidAccountCache.reputation_tier(attrs.rater_did),
      level: attrs.level,
      tags: attrs.tags |> Enum.uniq() |> Enum.sort(),
      intent_id: attrs.intent_id,
      signed_intent: attrs.signed_intent,
      inserted_at: now,
      updated_at: now
    }

    changeset =
      ForumHostContextNoteRating.changeset(%ForumHostContextNoteRating{}, rating_attrs)

    case Repo.insert(changeset,
           on_conflict:
             {:replace,
              [
                :rater_did,
                :rater_tier,
                :level,
                :tags,
                :intent_id,
                :signed_intent,
                :updated_at
              ]},
           conflict_target: [:note_id, :rater_key],
           returning: true
         ) do
      {:ok, rating} -> {:ok, :stored, public_rating(rating)}
      {:error, _changeset} -> {:error, :rating_conflict}
    end
  end

  defp score(%{withdrawn: true} = note),
    do: base_result(note, "withdrawn", [], [], nil)

  defp score(note) do
    ratings = ratings_for(note.note_id)
    counts = Enum.frequencies_by(ratings, & &1.level)
    total = length(ratings)
    verified = Enum.count(ratings, &verified_human?/1)
    score = mean_score(ratings)
    tag_counts = ratings |> Enum.flat_map(& &1.tags) |> Enum.frequencies()
    top_tags = top_tags(tag_counts)

    {status, reasons} =
      cond do
        hidden_reason = Moderation.context_note_hidden_reason(note.note_id, note.board_id) ->
          {"removed_by_host", ["host_moderation:#{hidden_reason}"]}

        target_changed?(note) ->
          {"target_changed", ["target_revision_changed"]}

        not quorum?(total, verified) ->
          {"needs_more_ratings", ["quorum_not_met"]}

        helpful?(score, total, tag_counts) ->
          {"helpful", ["helpful_threshold_met", "quality_tag_guard_passed"]}

        not_helpful?(score, tag_counts) ->
          {"not_helpful", ["not_helpful_threshold_met"]}

        true ->
          {"disputed", ["quorum_met_without_consensus"]}
      end

    base_result(note, status, reasons, top_tags, score, %{
      rating_count: total,
      level_counts: %{
        helpful: Map.get(counts, "helpful", 0),
        somewhat_helpful: Map.get(counts, "somewhat_helpful", 0),
        not_helpful: Map.get(counts, "not_helpful", 0)
      },
      verified_human_count: verified,
      input_hash: input_hash(ratings)
    })
  end

  defp base_result(note, status, reasons, top_tags, score, extra \\ %{}) do
    Map.merge(
      %{
        note_id: note.note_id,
        target_ref: note.payload["targetEntityId"],
        board_id: note.board_id,
        status: status,
        score: score && Float.round(score, 4),
        rating_count: 0,
        level_counts: %{helpful: 0, somewhat_helpful: 0, not_helpful: 0},
        verified_human_count: 0,
        top_tags: top_tags,
        reason_codes: reasons,
        scorer_id: @scorer_id,
        scorer_version: @scorer_version,
        evaluated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        input_hash: input_hash([])
      },
      extra
    )
  end

  defp note_snapshot(note_id) do
    case OpStore.latest_entity_op("context_note", note_id) do
      nil ->
        {:error, :context_note_not_found}

      %{op_type: "delete"} ->
        case OpStore.create_op("context_note", note_id) do
          nil -> {:error, :context_note_not_found}
          create -> snapshot(create, true)
        end

      latest ->
        snapshot(latest, false)
    end
  end

  defp snapshot(op, withdrawn) do
    with {:ok, payload} <- decode_payload(op.payload),
         create when not is_nil(create) <- OpStore.create_op("context_note", op.entity_id) do
      {:ok,
       %{
         note_id: op.entity_id,
         author_did: create.author_did,
         payload: payload,
         board_id: payload["boardId"] || payload["board_id"],
         withdrawn: withdrawn
       }}
    else
      _ -> {:error, :invalid_context_note}
    end
  end

  defp reject_self_rating(author_did, rater_did) do
    if MigrationStore.equivalent?(author_did, rater_did),
      do: {:error, :self_rating_forbidden},
      else: :ok
  end

  defp rating_by_intent(intent_id) do
    Repo.one(from(r in ForumHostContextNoteRating, where: r.intent_id == ^intent_id, limit: 1))
  end

  defp ratings_for(note_id) do
    Repo.all(
      from(r in ForumHostContextNoteRating,
        where: r.note_id == ^note_id,
        order_by: [asc: r.rater_key]
      )
    )
  end

  defp verified_human?(rating),
    do: rating.rater_tier in ["verified_human", "unique_human"]

  defp quorum?(total, verified), do: total >= 10 or (total >= 5 and verified >= 2)

  defp mean_score([]), do: 0.0

  defp mean_score(ratings) do
    Enum.sum(Enum.map(ratings, &Map.fetch!(@level_values, &1.level))) / length(ratings)
  end

  defp helpful?(score, total, tag_counts) do
    score >= 0.8 and not critical_tag_blocked?(tag_counts, total) and
      Enum.any?(@helpful_tags, &(Map.get(tag_counts, &1, 0) >= 2))
  end

  defp not_helpful?(score, tag_counts) do
    score <= 0.3 and Enum.any?(@not_helpful_tags, &(Map.get(tag_counts, &1, 0) >= 2))
  end

  defp critical_tag_blocked?(_tag_counts, 0), do: false

  defp critical_tag_blocked?(tag_counts, total) do
    Enum.any?(@critical_tags, &(Map.get(tag_counts, &1, 0) / total >= 0.3))
  end

  defp top_tags(tag_counts) do
    tag_counts
    |> Enum.filter(fn {_tag, count} -> count >= 2 end)
    |> Enum.sort_by(fn {tag, count} -> {-count, tag} end)
    |> Enum.take(2)
    |> Enum.map(fn {tag, count} -> %{tag: tag, count: count} end)
  end

  defp target_changed?(note) do
    payload = note.payload

    case OpStore.latest_entity_op(payload["targetEntityType"], payload["targetEntityId"]) do
      %{op_id: op_id, op_type: op_type} -> op_type == "delete" or op_id != payload["targetOpId"]
      nil -> true
    end
  end

  defp input_hash(ratings) do
    input =
      ratings
      |> Enum.map(fn rating ->
        [rating.rater_key, rating.level, Enum.sort(rating.tags) |> Enum.join(",")]
        |> Enum.join("|")
      end)
      |> Enum.sort()
      |> Enum.join("\n")

    "sha256:" <> (:crypto.hash(:sha256, input) |> Base.encode16(case: :lower))
  end

  defp rater_key(did) do
    canonical = MigrationStore.canonical_did(did)
    secret = Application.fetch_env!(:ansible_relay, :community_notes_rater_hmac_secret)

    :crypto.mac(:hmac, :sha256, secret, canonical)
    |> Base.url_encode64(padding: false)
  end

  defp public_rating(rating) do
    %{
      note_id: rating.note_id,
      rater_key: rating.rater_key,
      level: rating.level,
      tags: rating.tags,
      updated_at: rating.updated_at && DateTime.to_iso8601(rating.updated_at)
    }
  end

  defp decode_payload(payload) when is_map(payload), do: {:ok, payload}

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = value} ->
        {:ok, value}

      _ ->
        with {:ok, decoded} <- Base.decode64(payload),
             {:ok, %{} = value} <- Jason.decode(decoded) do
          {:ok, value}
        else
          _ -> {:error, :invalid_context_note}
        end
    end
  end

  defp decode_payload(_payload), do: {:error, :invalid_context_note}
end
