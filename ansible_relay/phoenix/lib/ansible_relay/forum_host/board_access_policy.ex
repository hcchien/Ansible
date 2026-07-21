defmodule AnsibleRelay.ForumHost.BoardAccessPolicy do
  @moduledoc """
  Strict parser for versioned Board Access Policy documents.

  The initial release persists only the open/public policy. Credential-gated
  modes fail closed until OID4VP verification and every authoritative read and
  write chokepoint are enabled together.
  """

  @default %{
    "version" => 1,
    "discovery" => "public",
    "read" => %{"requirement" => "public"},
    "post" => %{"requirement" => "posting_policy"},
    "requirements" => %{},
    "capability_ttl_seconds" => 300,
    "content_visibility" => "public",
    "federation" => "enabled"
  }
  @keys Map.keys(@default) |> MapSet.new()

  def default, do: @default

  def validate(policy) when is_map(policy) do
    keys = policy |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()

    cond do
      not MapSet.subset?(keys, @keys) ->
        {:error, :unknown_access_policy_field}

      value(policy, "version") != 1 ->
        {:error, :unsupported_access_policy_version}

      value(policy, "discovery") != "public" ->
        {:error, :protected_access_policy_not_enabled}

      value(value(policy, "read", %{}), "requirement") != "public" ->
        {:error, :protected_access_policy_not_enabled}

      value(policy, "content_visibility") != "public" ->
        {:error, :protected_access_policy_not_enabled}

      value(policy, "federation") not in ["enabled", "disabled"] ->
        {:error, :invalid_federation_policy}

      not is_map(value(policy, "requirements", %{})) ->
        {:error, :invalid_access_requirements}

      value(policy, "requirements", %{}) != %{} ->
        {:error, :protected_access_policy_not_enabled}

      not valid_ttl?(value(policy, "capability_ttl_seconds")) ->
        {:error, :invalid_capability_ttl}

      true ->
        :ok
    end
  end

  def validate(_policy), do: {:error, :invalid_access_policy}

  defp valid_ttl?(ttl), do: is_integer(ttl) and ttl >= 60 and ttl <= 900

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, String.to_atom(key), default))
end
