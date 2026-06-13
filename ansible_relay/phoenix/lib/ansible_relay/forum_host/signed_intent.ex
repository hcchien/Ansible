defmodule AnsibleRelay.ForumHost.SignedIntent do
  @moduledoc "Canonical JSON and verification for app-originated Forum Host intents."

  alias AnsibleRelay.ForumHost.Store
  alias AnsibleRelay.{IdentityCache, SigVerifier}

  @create_board_type "io.trisaura.forum.createBoard"
  @create_board_action "create_board"
  @create_board_version 1
  @report_content_type "io.trisaura.forum.reportContent"
  @report_content_action "report_content"
  @report_content_version 1
  @report_required_fields ~w(target_kind target_ref board_id reason_code)
  @default_clock_skew_seconds 0
  @default_max_age_seconds 600

  def verify_create_board(params) when is_map(params) do
    with :ok <- require_string(params, "signature", :missing_signature),
         :ok <- require_string(params, "author_did", :missing_author_did),
         :ok <- require_string(params, "intent_id", :missing_intent_id),
         :ok <- require_string(params, "target_forum_host", :missing_target_forum_host),
         :ok <- require_string(params, "action", :missing_action),
         :ok <- require_string(params, "created_at", :missing_created_at),
         :ok <- require_board_title(params),
         :ok <- require_type(params, @create_board_type),
         :ok <- require_version(params, @create_board_version),
         :ok <- require_action(params, @create_board_action),
         :ok <- require_target_host(params["target_forum_host"]),
         :ok <- require_timestamp_window(params),
         {:ok, public_key_hex} <- public_key(params["author_did"]),
         true <-
           SigVerifier.verify_ed25519(
             public_key_hex,
             canonical_json(params),
             params["signature"]
           ) do
      {:ok, create_board_attrs(params)}
    else
      false -> {:error, :invalid_signature}
      {:error, error} -> {:error, error}
    end
  end

  def verify_create_board(_params), do: {:error, :invalid_intent}

  @doc """
  Verifies a `report_content` intent (the app rail for content reports).
  Same envelope as `create_board`: audience-bound, time-windowed, and
  Ed25519-signed over the canonical JSON by the reporter's anchored DID.
  """
  def verify_report_content(params) when is_map(params) do
    with :ok <- require_string(params, "signature", :missing_signature),
         :ok <- require_string(params, "author_did", :missing_author_did),
         :ok <- require_string(params, "intent_id", :missing_intent_id),
         :ok <- require_string(params, "target_forum_host", :missing_target_forum_host),
         :ok <- require_string(params, "action", :missing_action),
         :ok <- require_string(params, "created_at", :missing_created_at),
         :ok <- require_report_payload(params),
         :ok <- require_type(params, @report_content_type),
         :ok <- require_version(params, @report_content_version),
         :ok <- require_action(params, @report_content_action),
         :ok <- require_target_host(params["target_forum_host"]),
         :ok <- require_timestamp_window(params),
         {:ok, public_key_hex} <- public_key(params["author_did"]),
         true <-
           SigVerifier.verify_ed25519(
             public_key_hex,
             canonical_json(params),
             params["signature"]
           ) do
      {:ok, report_content_attrs(params)}
    else
      false -> {:error, :invalid_signature}
      {:error, error} -> {:error, error}
    end
  end

  def verify_report_content(_params), do: {:error, :invalid_intent}

  def canonical_json(value) when is_map(value) do
    value
    |> Map.delete("signature")
    |> Map.delete(:signature)
    |> encode_canonical()
  end

  def canonical_json(value), do: encode_canonical(value)

  defp create_board_attrs(params) do
    board = params["board"]

    [
      {"description", :description},
      {"language", :language},
      {"tags", :tags},
      {"permissions", :permissions},
      {"posting_policy", :posting_policy},
      {"moderation_policy", :moderation_policy}
    ]
    |> Enum.reduce(
      %{
        intent_id: params["intent_id"],
        author_did: params["author_did"],
        title: board["title"]
      },
      fn {payload_key, attr_key}, attrs ->
        if Map.has_key?(board, payload_key) and not is_nil(board[payload_key]) do
          Map.put(attrs, attr_key, board[payload_key])
        else
          attrs
        end
      end
    )
  end

  defp report_content_attrs(params) do
    report = params["report"]

    %{
      intent_id: params["intent_id"],
      reporter_did: params["author_did"],
      target_kind: report["target_kind"],
      target_ref: report["target_ref"],
      board_id: report["board_id"],
      reason_code: report["reason_code"],
      note: report["note"]
    }
  end

  defp require_report_payload(%{"report" => %{} = report}) do
    if Enum.all?(@report_required_fields, fn field ->
         is_binary(report[field]) and String.trim(report[field]) != ""
       end) do
      :ok
    else
      {:error, :invalid_report}
    end
  end

  defp require_report_payload(_params), do: {:error, :invalid_report}

  defp encode_canonical(value) when is_map(value) do
    value
    |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
    |> Enum.sort_by(fn {key, _entry_value} -> key end)
    |> Enum.map(fn {key, entry_value} ->
      Jason.encode!(key) <> ":" <> encode_canonical(entry_value)
    end)
    |> then(&("{" <> Enum.join(&1, ",") <> "}"))
  end

  defp encode_canonical(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &encode_canonical/1) <> "]"
  end

  defp encode_canonical(value), do: Jason.encode!(value)

  defp require_string(params, key, error) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, error}, else: :ok

      _value ->
        {:error, error}
    end
  end

  defp require_board_title(%{"board" => %{"title" => title}}) when is_binary(title) do
    if String.trim(title) == "", do: {:error, :invalid_board}, else: :ok
  end

  defp require_board_title(_params), do: {:error, :invalid_board}

  defp require_type(%{"type" => expected}, expected), do: :ok
  defp require_type(_params, _expected), do: {:error, :invalid_intent_type}

  defp require_version(%{"version" => expected}, expected), do: :ok
  defp require_version(_params, _expected), do: {:error, :invalid_intent_version}

  defp require_action(%{"action" => expected}, expected), do: :ok
  defp require_action(_params, _expected), do: {:error, :invalid_action}

  defp require_target_host(target) do
    if normalize_origin(target) == normalize_origin(Store.base_url()) do
      :ok
    else
      {:error, :audience_mismatch}
    end
  end

  defp require_timestamp_window(params) do
    with {:ok, created_at} <- parse_timestamp(params["created_at"], :invalid_created_at),
         {:ok, expires_at} <- parse_timestamp(params["expires_at"], :invalid_expiry),
         :ok <- require_created_at_not_future(created_at),
         :ok <- require_expires_at_future(expires_at),
         :ok <- require_max_intent_age(created_at, expires_at) do
      :ok
    end
  end

  defp parse_timestamp(value, error) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, parsed}
      _error -> {:error, error}
    end
  end

  defp parse_timestamp(_value, error), do: {:error, error}

  defp require_created_at_not_future(created_at) do
    latest_allowed_created_at = DateTime.add(DateTime.utc_now(), clock_skew_seconds(), :second)

    if DateTime.compare(created_at, latest_allowed_created_at) in [:lt, :eq] do
      :ok
    else
      {:error, :created_at_in_future}
    end
  end

  defp require_expires_at_future(expires_at) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
      :ok
    else
      {:error, :expired_intent}
    end
  end

  defp require_max_intent_age(created_at, expires_at) do
    cond do
      DateTime.compare(expires_at, created_at) != :gt ->
        {:error, :invalid_expiry}

      DateTime.diff(expires_at, created_at, :second) <= max_age_seconds() ->
        :ok

      true ->
        {:error, :intent_lifetime_too_long}
    end
  end

  defp clock_skew_seconds do
    Application.get_env(
      :ansible_relay,
      :forum_host_signed_intent_clock_skew_seconds,
      @default_clock_skew_seconds
    )
  end

  defp max_age_seconds do
    Application.get_env(
      :ansible_relay,
      :forum_host_signed_intent_max_age_seconds,
      @default_max_age_seconds
    )
  end

  defp public_key(did) do
    if IdentityCache.verified?(did) do
      case IdentityCache.public_key_hex(did) do
        public_key_hex when is_binary(public_key_hex) -> {:ok, public_key_hex}
        _missing -> {:error, :unknown_did}
      end
    else
      {:error, :unknown_did}
    end
  end

  defp normalize_origin(value) when is_binary(value) do
    uri = URI.parse(value)
    port = if uri.port, do: ":#{uri.port}", else: ""
    "#{String.downcase(uri.scheme || "")}://#{String.downcase(uri.host || "")}#{port}"
  end

  defp normalize_origin(_value), do: ""
end
