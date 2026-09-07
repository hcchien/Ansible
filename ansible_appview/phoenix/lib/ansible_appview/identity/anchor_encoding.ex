defmodule AnsibleAppview.Identity.AnchorEncoding do
  @moduledoc "Pure canonical identity-anchor encoding; parity tested with Relay fixtures."
  alias AnsibleAppview.DidElix
  @body_keys_v2 ~w(type schema_version did handle identity_key also_known_as
                   custody_class devices prev_anchor_cid reason created_at)
  @body_keys_v3 ~w(type schema_version did handle identity_key identity_key_algorithm
                   also_known_as custody_class devices prev_anchor_cid reason created_at)
  @body_keys_v4 ~w(type schema_version did handle identity_key identity_key_algorithm genesis_commitment
                   also_known_as custody_class devices prev_anchor_cid reason created_at)
  @device_keys ~w(device_id device_key custody_class enrolled_at attestation_sig)
  # The fields an enrolled device's `attestation_sig` actually signs: the
  # device record MINUS `attestation_sig`, in the same order (design
  # §"Anchor as a Self-Certifying Object"; the leading keys of the Dart
  # `AnchorDeviceRecord.toCanonicalMap`, with the trailing `attestation_sig`
  # dropped from the signed message).
  @device_attestation_keys ~w(device_id device_key custody_class enrolled_at)
  @anchor_type "io.trisaura.identity.anchor"

  # --- Canonical encoding (byte-for-byte with the Dart foundation) ---

  @doc "Canonical body JSON (no signatures), fixed key order, no whitespace."
  def canonical_body(anchor) when is_map(anchor) do
    body_keys(anchor)
    |> Enum.map(fn key -> encode_pair(key, body_value(key, anchor)) end)
    |> wrap_object()
  end

  defp body_keys(anchor) do
    if schema_version(anchor) >= 4,
      do: @body_keys_v4,
      else: if(schema_version(anchor) >= 3, do: @body_keys_v3, else: @body_keys_v2)
  end

  defp body_value("type", _anchor), do: @anchor_type
  defp body_value("schema_version", anchor), do: schema_version(anchor)
  defp body_value("also_known_as", anchor), do: also_known_as(anchor)
  defp body_value("devices", anchor), do: {:devices, devices(anchor)}
  defp body_value(key, anchor), do: fetch(anchor, key)

  # A JSON array of alias strings; defaults to [] so the canonical body matches
  # the Dart `also_known_as: const []` default (never `null`).
  defp also_known_as(anchor) do
    case fetch(anchor, "also_known_as") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp schema_version(anchor) do
    case fetch(anchor, "schema_version") do
      nil -> 1
      v when is_integer(v) -> v
      _ -> 0
    end
  end

  defp devices(anchor) do
    case fetch(anchor, "devices") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp encode_pair("devices", {:devices, list}) do
    inner = Enum.map_join(list, ",", &canonical_device/1)
    Jason.encode!("devices") <> ":[" <> inner <> "]"
  end

  defp encode_pair("genesis_commitment", commitment) when is_map(commitment) do
    Jason.encode!("genesis_commitment") <> ":" <> DidElix.canonical_v1_commitment(commitment)
  end

  defp encode_pair(key, value) do
    Jason.encode!(key) <> ":" <> Jason.encode!(value)
  end

  defp canonical_device(device) do
    @device_keys
    |> Enum.map(fn key -> Jason.encode!(key) <> ":" <> Jason.encode!(fetch(device, key)) end)
    |> wrap_object()
  end

  @doc """
  Canonical bytes an enrolled device's `attestation_sig` covers: the device
  record minus `attestation_sig`, fixed key order, no whitespace. The identity
  key signs THIS message to attest the device key.

  Mirrors the Dart `AnchorDeviceRecord.toCanonicalMap`
  (`ansible_core/store/lib/src/entities/identity_anchor.dart`) with the
  trailing `attestation_sig` field excluded from the signed message.
  """
  def device_attestation_message(device) when is_map(device) do
    @device_attestation_keys
    |> Enum.map(fn key -> Jason.encode!(key) <> ":" <> Jason.encode!(fetch(device, key)) end)
    |> wrap_object()
  end

  defp wrap_object(entries), do: "{" <> Enum.join(entries, ",") <> "}"

  @doc "Content identifier of an anchor object: `sha256:<lowercase hex>`."
  def compute_cid(anchor) when is_map(anchor), do: cid_of_body(canonical_body(anchor))

  def cid_of_body(body) when is_binary(body) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, body), case: :lower)
  end

  # Accept both string and atom keys from JSON params / structs.
  defp fetch(map, key) when is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, String.to_existing_atom(key))
    end
  rescue
    ArgumentError -> nil
  end
end
