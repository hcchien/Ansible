defmodule AnsibleRelay.ForumHost.ReportReason do
  @moduledoc """
  Fixed reason-code enum for content reports and moderation actions.

  Constitution Base Rules 6/7 make this mandatory: every report and every
  moderation effect carries a reason code from this single enum, so outcomes
  stay explainable to the affected author. `other` requires a non-empty
  free-text note (visible to moderators only — never on a public surface).
  """

  @codes ~w(spam harassment illegal_content off_topic impersonation other)

  @doc "All valid reason codes, in canonical order."
  def codes, do: @codes

  @doc "Returns true when the value is a known reason code."
  def valid?(code), do: code in @codes

  @doc "Returns true when the reason code requires a non-empty note."
  def requires_note?("other"), do: true
  def requires_note?(_code), do: false

  @doc """
  Validates a reason code together with its optional note. A missing note for
  `other` is reported as `:invalid_reason_code` — the reason is incomplete.
  """
  def validate(code, note) do
    cond do
      not valid?(code) -> {:error, :invalid_reason_code}
      requires_note?(code) and blank?(note) -> {:error, :invalid_reason_code}
      true -> :ok
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end
