defmodule AnsibleRelay.SafetyReportIntent do
  @moduledoc "Verifies audience-bound, DID-signed safety report intents."

  alias AnsibleRelay.ForumHost.{ReportReason, SignedIntent, Store}
  alias AnsibleRelay.IdentityCache

  @intent_type "io.trisaura.safety.report"
  @version 1
  @actions ~w(report_content block_user)
  @max_age_seconds 600

  def verify(params) when is_map(params) do
    with :ok <- require_string(params, "signature", :missing_signature),
         :ok <- require_string(params, "author_did", :missing_author_did),
         :ok <- require_string(params, "intent_id", :missing_intent_id),
         :ok <- require_string(params, "target_relay", :missing_target_relay),
         :ok <- require_string(params, "action", :invalid_action),
         :ok <- require_string(params, "created_at", :invalid_created_at),
         :ok <- require_string(params, "expires_at", :invalid_expiry),
         :ok <- require_envelope(params),
         {:ok, attrs} <- report_attrs(params),
         :ok <- ReportReason.validate(attrs.reason_code, attrs.note),
         :ok <- require_audience(params["target_relay"]),
         :ok <- require_timestamp_window(params),
         :ok <- require_known_did(params["author_did"]),
         true <-
           IdentityCache.verify_signature(
             params["author_did"],
             SignedIntent.canonical_json(params),
             params["signature"]
           ) do
      {:ok, attrs}
    else
      false -> {:error, :invalid_signature}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_), do: {:error, :invalid_safety_event}

  defp require_envelope(params) do
    if params["type"] == @intent_type and params["version"] == @version and
         params["action"] in @actions do
      :ok
    else
      {:error, :invalid_safety_event}
    end
  end

  defp report_attrs(%{"report" => report} = params) when is_map(report) do
    attrs = %{
      event_type: params["action"],
      reporter_did: params["author_did"],
      subject_did: report["subject_did"],
      target_kind: report["target_kind"],
      target_ref: report["target_ref"],
      reason_code: report["reason_code"],
      note: report["note"]
    }

    if present?(attrs.target_kind) and present?(attrs.target_ref) and
         present?(attrs.reason_code) and
         (attrs.event_type != "block_user" or present?(attrs.subject_did)) do
      {:ok, attrs}
    else
      {:error, :invalid_safety_event}
    end
  end

  defp report_attrs(_), do: {:error, :invalid_safety_event}

  defp require_audience(value) do
    if normalize_origin(value) == normalize_origin(Store.base_url()),
      do: :ok,
      else: {:error, :audience_mismatch}
  end

  defp require_timestamp_window(params) do
    with {:ok, created_at, _} <- DateTime.from_iso8601(params["created_at"]),
         {:ok, expires_at, _} <- DateTime.from_iso8601(params["expires_at"]),
         true <-
           DateTime.compare(created_at, DateTime.add(DateTime.utc_now(), 30, :second)) != :gt,
         true <- DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
         true <- DateTime.compare(expires_at, created_at) == :gt,
         true <- DateTime.diff(expires_at, created_at, :second) <= @max_age_seconds do
      :ok
    else
      _ -> {:error, :invalid_expiry}
    end
  end

  defp require_known_did(did) do
    if IdentityCache.verified?(did), do: :ok, else: {:error, :unknown_did}
  end

  defp require_string(params, key, error) do
    if present?(params[key]), do: :ok, else: {:error, error}
  end

  defp normalize_origin(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.downcase()
  end

  defp normalize_origin(_), do: ""
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
