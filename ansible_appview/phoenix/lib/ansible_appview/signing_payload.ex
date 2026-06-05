defmodule AnsibleAppview.SigningPayload do
  @moduledoc """
  Canonical signing payload for relay ops — byte-identical to the relay
  (`OpsController.signing_payload/1`) and the app (`OpSignaturePayload`), so the
  AppView can re-verify Ed25519 signatures over ingested ops.
  """

  @spec build(map()) :: String.t()
  def build(op) do
    %{
      "author_did" => op["author_did"],
      "entity_id" => op["entity_id"],
      "entity_type" => op["entity_type"],
      "op_id" => op["op_id"],
      "op_type" => op["op_type"],
      "payload" => op["payload"]
    }
    |> canonical_json()
  end

  def canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  def canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  def canonical_json(value), do: Jason.encode!(value)
end
