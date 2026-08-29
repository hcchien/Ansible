defmodule AnsibleRelay.ForumHost.Deliberations do
  @moduledoc """
  Board-owned, multi-statement deliberations.

  Canonical DIDs are used only to authorize host writes. Public responses and
  analysis use a keyed, deliberation-scoped participant identifier that is
  never returned by this module's serializers.
  """

  import Ecto.Query

  alias AnsibleRelay.Db.{
    ForumHostBoard,
    ForumHostDeliberation,
    ForumHostDeliberationAnalysisSnapshot,
    ForumHostDeliberationStatement,
    ForumHostDeliberationVote
  }

  alias AnsibleRelay.Repo

  @algorithm "elix-deliberation-aggregates"
  @algorithm_version "1.0.0"
  @seed 0
  @export_ttl_seconds 86_400

  def list(%ForumHostBoard{} = board) do
    participant_counts =
      from(v in ForumHostDeliberationVote,
        group_by: v.deliberation_id,
        select: {v.deliberation_id, count(v.participant_key, :distinct)}
      )
      |> Repo.all()
      |> Map.new()

    statement_counts =
      from(s in ForumHostDeliberationStatement,
        where: s.state == "accepted",
        group_by: s.deliberation_id,
        select: {s.deliberation_id, count(s.id)}
      )
      |> Repo.all()
      |> Map.new()

    from(d in ForumHostDeliberation,
      where: d.hosted_board_id == ^board.hosted_board_id,
      order_by: [desc: d.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn deliberation ->
      summary_json(deliberation,
        participant_count: Map.get(participant_counts, deliberation.id, 0),
        statement_count: Map.get(statement_counts, deliberation.id, 0)
      )
    end)
  end

  def get(%ForumHostBoard{} = board, id) do
    case Repo.get(ForumHostDeliberation, id) do
      %ForumHostDeliberation{hosted_board_id: hosted_board_id} = deliberation
      when hosted_board_id == board.hosted_board_id ->
        {:ok, deliberation}

      _ ->
        {:error, :deliberation_not_found}
    end
  end

  def create(%ForumHostBoard{} = board, attrs, author_did, intent_id) do
    attrs =
      attrs
      |> atomize_keys()
      |> Map.merge(%{
        hosted_board_id: board.hosted_board_id,
        creator_did: author_did,
        last_intent_id: intent_id,
        access_policy_version: board.access_policy_version
      })

    changeset = ForumHostDeliberation.changeset(%ForumHostDeliberation{}, attrs)

    case Repo.insert(changeset) do
      {:ok, deliberation} -> {:ok, detail_json(deliberation, [], empty_report(deliberation))}
      {:error, %Ecto.Changeset{} = changeset} -> resolve_create_replay(changeset, intent_id)
    end
  end

  def submit_statement(
        %ForumHostBoard{} = board,
        deliberation_id,
        text,
        author_did,
        intent_id
      ) do
    with {:ok, deliberation} <- get(board, deliberation_id),
         :ok <- collecting?(deliberation),
         {:ok, participant_key} <- participant_key(deliberation.id, author_did) do
      attrs = %{
        deliberation_id: deliberation.id,
        author_did: author_did,
        author_participant_key: participant_key,
        text: text,
        state: "accepted",
        last_intent_id: intent_id
      }

      case %ForumHostDeliberationStatement{}
           |> ForumHostDeliberationStatement.changeset(attrs)
           |> Repo.insert() do
        {:ok, statement} -> {:ok, statement_json(statement, nil)}
        {:error, %Ecto.Changeset{} = changeset} -> resolve_statement_replay(changeset, intent_id)
      end
    end
  end

  def cast_vote(
        %ForumHostBoard{} = board,
        deliberation_id,
        statement_id,
        stance,
        author_did,
        intent_id,
        supersedes_intent_id
      ) do
    with {:ok, deliberation} <- get(board, deliberation_id),
         :ok <- collecting?(deliberation),
         {:ok, statement} <- accepted_statement(deliberation.id, statement_id),
         true <- stance in ~w(agree disagree pass),
         {:ok, participant_key} <- participant_key(deliberation.id, author_did) do
      Repo.transaction(fn ->
        current =
          from(v in ForumHostDeliberationVote,
            where:
              v.deliberation_id == ^deliberation.id and v.statement_id == ^statement.id and
                v.participant_key == ^participant_key,
            lock: "FOR UPDATE"
          )
          |> Repo.one()

        case vote_change(current, supersedes_intent_id) do
          :ok ->
            attrs = %{
              deliberation_id: deliberation.id,
              statement_id: statement.id,
              participant_key: participant_key,
              stance: stance,
              last_intent_id: intent_id,
              access_policy_version: board.access_policy_version
            }

            result =
              case current do
                nil ->
                  %ForumHostDeliberationVote{}
                  |> ForumHostDeliberationVote.changeset(attrs)
                  |> Repo.insert()

                vote ->
                  vote
                  |> ForumHostDeliberationVote.changeset(attrs)
                  |> Repo.update()
              end

            case result do
              {:ok, vote} -> vote
              {:error, changeset} -> Repo.rollback(changeset_error(changeset))
            end

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, vote} ->
          {:ok,
           %{
             accepted: true,
             statement_id: statement.id,
             stance: vote.stance,
             last_intent_id: vote.last_intent_id
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      false -> {:error, :invalid_deliberation_stance}
      {:error, _} = error -> error
    end
  end

  def withdraw_vote(
        %ForumHostBoard{} = board,
        deliberation_id,
        statement_id,
        author_did,
        supersedes_intent_id
      ) do
    with {:ok, deliberation} <- get(board, deliberation_id),
         :ok <- collecting?(deliberation),
         {:ok, _statement} <- accepted_statement(deliberation.id, statement_id),
         {:ok, participant_key} <- participant_key(deliberation.id, author_did) do
      Repo.transaction(fn ->
        current =
          from(v in ForumHostDeliberationVote,
            where:
              v.deliberation_id == ^deliberation.id and v.statement_id == ^statement_id and
                v.participant_key == ^participant_key,
            lock: "FOR UPDATE"
          )
          |> Repo.one()

        cond do
          is_nil(current) -> Repo.rollback(:vote_not_found)
          current.last_intent_id != supersedes_intent_id -> Repo.rollback(:stale_vote_intent)
          true -> Repo.delete!(current)
        end
      end)
      |> case do
        {:ok, _vote} -> {:ok, %{withdrawn: true, statement_id: statement_id}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def detail(%ForumHostBoard{} = board, id, viewer_did \\ nil) do
    with {:ok, deliberation} <- get(board, id) do
      statements = accepted_statements(deliberation.id)
      report = report_for(deliberation, statements)
      viewer_keys = viewer_vote_map(deliberation.id, viewer_did)

      {:ok,
       detail_json(
         deliberation,
         Enum.map(statements, &statement_json(&1, Map.get(viewer_keys, &1.id))),
         report
       )}
    end
  end

  def viewer_responses(%ForumHostBoard{} = board, id, viewer_did) do
    with {:ok, deliberation} <- get(board, id),
         true <- is_binary(viewer_did) and viewer_did != "" do
      {:ok, viewer_vote_map(deliberation.id, viewer_did)}
    else
      false -> {:error, :invalid_participant}
      {:error, _} = error -> error
    end
  end

  def report(%ForumHostBoard{} = board, id) do
    with {:ok, deliberation} <- get(board, id) do
      statements = accepted_statements(deliberation.id)
      result = report_for(deliberation, statements)
      persist_snapshot(deliberation, result)
    end
  end

  def export(%ForumHostBoard{} = board, id, view) do
    with {:ok, deliberation} <- get(board, id),
         true <- view in ~w(report aggregates pseudonymous_matrix),
         :ok <- export_allowed?(deliberation, view),
         statements <- accepted_statements(deliberation.id),
         report <- report_for(deliberation, statements),
         :ok <- export_threshold_met?(deliberation, report, view) do
      export_id = Ecto.UUID.generate()
      expires_at = DateTime.add(DateTime.utc_now(), @export_ttl_seconds, :second)

      base = %{
        export_id: export_id,
        deliberation_id: deliberation.id,
        board_id: board.board_id,
        view: view,
        expires_at: expires_at,
        manifest: %{
          dataset_digest: report.dataset_digest,
          algorithm: report.algorithm,
          algorithm_version: report.algorithm_version,
          access_policy_version: board.access_policy_version,
          missing_value_semantics: "not_present",
          pass_value: "pass",
          participant_identifiers: "export_scoped_pseudonyms"
        },
        report: report
      }

      if view == "pseudonymous_matrix" do
        rows = export_rows(deliberation.id, export_id)

        {:ok,
         Map.merge(base, %{
           statements: Enum.map(statements, &%{id: &1.id, text: &1.text}),
           responses: rows
         })}
      else
        {:ok, base}
      end
    else
      false -> {:error, :invalid_export_view}
      {:error, _} = error -> error
    end
  end

  defp accepted_statements(deliberation_id) do
    from(s in ForumHostDeliberationStatement,
      where: s.deliberation_id == ^deliberation_id and s.state == "accepted",
      order_by: [asc: s.inserted_at, asc: s.id]
    )
    |> Repo.all()
  end

  defp accepted_statement(deliberation_id, statement_id) do
    case Repo.get(ForumHostDeliberationStatement, statement_id) do
      %ForumHostDeliberationStatement{deliberation_id: ^deliberation_id, state: "accepted"} =
          statement ->
        {:ok, statement}

      _ ->
        {:error, :statement_not_found}
    end
  end

  defp collecting?(%ForumHostDeliberation{status: "collecting", closes_at: nil}), do: :ok

  defp collecting?(%ForumHostDeliberation{status: "collecting", closes_at: closes_at}) do
    if DateTime.compare(closes_at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :deliberation_closed}
  end

  defp collecting?(_), do: {:error, :deliberation_closed}

  defp vote_change(nil, supersedes) when supersedes in [nil, ""], do: :ok
  defp vote_change(nil, _), do: {:error, :stale_vote_intent}
  defp vote_change(%{last_intent_id: current}, current), do: :ok
  defp vote_change(_, _), do: {:error, :stale_vote_intent}

  defp report_for(deliberation, statements) do
    votes =
      from(v in ForumHostDeliberationVote,
        where: v.deliberation_id == ^deliberation.id,
        select: {v.statement_id, v.participant_key, v.stance}
      )
      |> Repo.all()

    participant_count = votes |> Enum.map(&elem(&1, 1)) |> MapSet.new() |> MapSet.size()

    aggregates =
      Enum.map(statements, fn statement ->
        stances =
          for {statement_id, _participant, stance} <- votes,
              statement_id == statement.id,
              do: stance

        agree = Enum.count(stances, &(&1 == "agree"))
        disagree = Enum.count(stances, &(&1 == "disagree"))
        pass = Enum.count(stances, &(&1 == "pass"))
        decisive = agree + disagree

        %{
          statement_id: statement.id,
          text: statement.text,
          agree: agree,
          disagree: disagree,
          pass: pass,
          response_count: length(stances),
          agree_ratio: if(decisive == 0, do: nil, else: agree / decisive)
        }
      end)

    digest = dataset_digest(statements, votes)

    consensus =
      aggregates
      |> Enum.filter(&is_number(&1.agree_ratio))
      |> Enum.sort_by(&{-&1.agree_ratio, -&1.response_count, &1.statement_id})

    disagreement =
      aggregates
      |> Enum.filter(&is_number(&1.agree_ratio))
      |> Enum.sort_by(&{abs(&1.agree_ratio - 0.5), -&1.response_count, &1.statement_id})

    cluster_status =
      if participant_count < deliberation.min_report_participants,
        do: "insufficient_participants",
        else: "aggregate_only"

    %{
      dataset_digest: digest,
      algorithm: @algorithm,
      algorithm_version: @algorithm_version,
      generated_at: DateTime.utc_now(),
      participant_count: participant_count,
      statement_count: length(statements),
      response_count: length(votes),
      statement_aggregates: aggregates,
      consensus: Enum.take(consensus, 10),
      disagreement: Enum.take(disagreement, 10),
      cluster_status: cluster_status,
      analysis_capabilities: ["statement_aggregates", "consensus_ranking"],
      privacy: %{
        min_report_participants: deliberation.min_report_participants,
        min_group_size: deliberation.min_group_size
      }
    }
  end

  defp persist_snapshot(deliberation, result) do
    attrs = %{
      deliberation_id: deliberation.id,
      dataset_digest: result.dataset_digest,
      algorithm: @algorithm,
      algorithm_version: @algorithm_version,
      seed: @seed,
      parameters: %{
        "min_report_participants" => deliberation.min_report_participants,
        "min_group_size" => deliberation.min_group_size
      },
      result: stringify_json(result),
      status: "complete",
      generated_at: result.generated_at
    }

    case %ForumHostDeliberationAnalysisSnapshot{}
         |> ForumHostDeliberationAnalysisSnapshot.changeset(attrs)
         |> Repo.insert() do
      {:ok, snapshot} ->
        {:ok,
         result
         |> Map.put(:generated_at, snapshot.generated_at)
         |> Map.put(:snapshot_id, snapshot.id)}

      {:error, _changeset} ->
        snapshot =
          Repo.get_by!(ForumHostDeliberationAnalysisSnapshot,
            deliberation_id: deliberation.id,
            dataset_digest: result.dataset_digest,
            algorithm_version: @algorithm_version
          )

        {:ok,
         result
         |> Map.put(:generated_at, snapshot.generated_at)
         |> Map.put(:snapshot_id, snapshot.id)}
    end
  end

  defp empty_report(deliberation), do: report_for(deliberation, [])

  defp dataset_digest(statements, votes) do
    payload = %{
      statements: Enum.map(statements, &%{id: &1.id, text: &1.text}),
      votes:
        votes
        |> Enum.sort()
        |> Enum.map(fn {statement_id, participant_key, stance} ->
          [statement_id, participant_key, stance]
        end)
    }

    Jason.encode!(payload)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp participant_key(deliberation_id, did) when is_binary(did) and did != "" do
    {:ok, keyed_digest("deliberation-participant-v1", deliberation_id <> "\0" <> did)}
  end

  defp participant_key(_, _), do: {:error, :invalid_participant}

  defp export_rows(deliberation_id, export_id) do
    from(v in ForumHostDeliberationVote,
      where: v.deliberation_id == ^deliberation_id,
      order_by: [asc: v.statement_id, asc: v.id],
      select: {v.participant_key, v.statement_id, v.stance}
    )
    |> Repo.all()
    |> Enum.map(fn {participant_key, statement_id, stance} ->
      %{
        export_participant_id:
          keyed_digest(
            "deliberation-export-participant-v1",
            export_id <> "\0" <> participant_key
          ),
        statement_id: statement_id,
        stance: stance
      }
    end)
  end

  defp keyed_digest(label, value) do
    secret = Application.fetch_env!(:ansible_relay, :sync_capability_secret)

    :crypto.mac(:hmac, :sha256, secret, label <> "\0" <> value)
    |> Base.url_encode64(padding: false)
  end

  defp export_allowed?(%{export_mode: "no_external_analysis"}, _),
    do: {:error, :deliberation_export_disabled}

  defp export_allowed?(%{export_mode: "aggregates_only"}, "pseudonymous_matrix"),
    do: {:error, :deliberation_matrix_export_disabled}

  defp export_allowed?(_, _), do: :ok

  defp export_threshold_met?(_deliberation, _report, view)
       when view in ["report", "aggregates"],
       do: :ok

  defp export_threshold_met?(deliberation, report, "pseudonymous_matrix") do
    if report.participant_count >= deliberation.min_report_participants,
      do: :ok,
      else: {:error, :insufficient_export_participants}
  end

  defp viewer_vote_map(_deliberation_id, nil), do: %{}

  defp viewer_vote_map(deliberation_id, did) do
    with {:ok, key} <- participant_key(deliberation_id, did) do
      from(v in ForumHostDeliberationVote,
        where: v.deliberation_id == ^deliberation_id and v.participant_key == ^key,
        select: {v.statement_id, %{stance: v.stance, last_intent_id: v.last_intent_id}}
      )
      |> Repo.all()
      |> Map.new()
    else
      _ -> %{}
    end
  end

  defp summary_json(deliberation, counts) do
    %{
      id: deliberation.id,
      board_id: deliberation.hosted_board_id,
      title: deliberation.title,
      prompt: deliberation.prompt,
      status: deliberation.status,
      export_mode: deliberation.export_mode,
      participant_count: Keyword.fetch!(counts, :participant_count),
      statement_count: Keyword.fetch!(counts, :statement_count),
      closes_at: deliberation.closes_at,
      created_at: deliberation.inserted_at,
      updated_at: deliberation.updated_at
    }
  end

  defp detail_json(deliberation, statements, report) do
    Map.merge(
      summary_json(deliberation,
        participant_count: report.participant_count,
        statement_count: length(statements)
      ),
      %{
        context: deliberation.context,
        statement_attribution: deliberation.statement_attribution,
        min_report_participants: deliberation.min_report_participants,
        min_group_size: deliberation.min_group_size,
        access_policy_version: deliberation.access_policy_version,
        statements: statements,
        report: report
      }
    )
  end

  defp statement_json(statement, viewer_response) do
    %{
      id: statement.id,
      text: statement.text,
      state: statement.state,
      created_at: statement.inserted_at,
      viewer_response: viewer_response
    }
  end

  defp resolve_create_replay(changeset, intent_id) do
    if changeset.errors[:last_intent_id] do
      case Repo.get_by(ForumHostDeliberation, last_intent_id: intent_id) do
        nil ->
          {:error, :invalid_deliberation}

        deliberation ->
          detail(%ForumHostBoard{hosted_board_id: deliberation.hosted_board_id}, deliberation.id)
      end
    else
      {:error, changeset_error(changeset)}
    end
  end

  defp resolve_statement_replay(changeset, intent_id) do
    if changeset.errors[:last_intent_id] do
      case Repo.get_by(ForumHostDeliberationStatement, last_intent_id: intent_id) do
        nil -> {:error, :invalid_deliberation_statement}
        statement -> {:ok, statement_json(statement, nil)}
      end
    else
      {:error, changeset_error(changeset)}
    end
  end

  defp changeset_error(changeset) do
    if changeset.valid?, do: :invalid_deliberation, else: :invalid_deliberation_payload
  end

  defp atomize_keys(attrs) when is_map(attrs) do
    allowed = %{
      "title" => :title,
      "prompt" => :prompt,
      "context" => :context,
      "status" => :status,
      "closes_at" => :closes_at,
      "statement_attribution" => :statement_attribution,
      "export_mode" => :export_mode,
      "min_report_participants" => :min_report_participants,
      "min_group_size" => :min_group_size
    }

    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_binary(key) ->
        case Map.fetch(allowed, key) do
          {:ok, atom} -> Map.put(acc, atom, value)
          :error -> acc
        end

      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)

      _, acc ->
        acc
    end)
  end

  defp stringify_json(value), do: Jason.decode!(Jason.encode!(value))
end
