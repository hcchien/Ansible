defmodule AnsibleRelay.ForumHost.BoardAccessPolicy do
  @moduledoc """
  Strict parser and evaluator for Board Access Policy v1.

  Policies are deliberately a small allowlisted language. Unknown fields,
  operators, credential types, and requirements fail closed. Membership
  evidence is board-scoped and must never be converted into global reputation.
  """

  @default %{
    "version" => 1,
    "discovery" => "public",
    "read" => %{"requirement" => "public"},
    "post" => %{"requirement" => "posting_policy"},
    "moderate" => %{"requirement" => "board_moderator"},
    "requirements" => %{},
    "capability_ttl_seconds" => 300,
    "content_visibility" => "public",
    "federation" => "enabled"
  }

  @top_keys Map.keys(@default) |> MapSet.new()
  @action_keys MapSet.new(["requirement"])
  @requirement_keys MapSet.new([
                      "credential_configuration_id",
                      "credential_type",
                      "trusted_issuers",
                      "claims",
                      "holder_binding",
                      "status"
                    ])
  @claim_keys MapSet.new(["path", "op", "value"])
  @status_keys MapSet.new(["required", "max_age_seconds"])
  @prohibited_claims MapSet.new(~w[
    nationalid legalname birthdate documentnumber passportnumber
    nationalidhash passportnumberhash rawproviderassertion
  ])
  @built_in_requirements ["public", "posting_policy", "board_moderator"]

  def default, do: @default

  def validate(policy) when is_map(policy) do
    with :ok <- exact_keys(policy, @top_keys, :unknown_access_policy_field),
         :ok <- require(policy, "version", &(&1 == 1), :unsupported_access_policy_version),
         :ok <-
           require(
             policy,
             "discovery",
             &(&1 in ["public", "credential_required"]),
             :invalid_discovery_policy
           ),
         :ok <- validate_action(value(policy, "read")),
         :ok <- validate_action(value(policy, "post")),
         :ok <- validate_action(value(policy, "moderate", %{"requirement" => "board_moderator"})),
         :ok <- validate_requirements(value(policy, "requirements")),
         :ok <- validate_references(policy),
         :ok <- require(policy, "capability_ttl_seconds", &valid_ttl?/1, :invalid_capability_ttl),
         :ok <- validate_visibility(value(policy, "content_visibility")),
         :ok <-
           require(
             policy,
             "federation",
             &(&1 in ["enabled", "disabled"]),
             :invalid_federation_policy
           ),
         :ok <- validate_privacy_combination(policy) do
      :ok
    end
  end

  def validate(_policy), do: {:error, :invalid_access_policy}

  def evaluate(policy, action, evidence) when action in [:discovery, :read, :post, :moderate] do
    with :ok <- validate(policy),
         requirement <- action_requirement(policy, action),
         :ok <- evaluate_requirement(requirement, value(policy, "requirements"), evidence) do
      :ok
    end
  end

  def evaluate(_policy, _action, _evidence), do: {:error, :invalid_access_action}

  def evaluate_for_requirement(policy, requirement, evidence) do
    with :ok <- validate(policy) do
      evaluate_requirement(requirement, value(policy, "requirements"), evidence)
    end
  end

  def requirement_for(policy, action) when action in [:discovery, :read, :post, :moderate] do
    with :ok <- validate(policy), do: {:ok, action_requirement(policy, action)}
  end

  def requirement_for(_policy, _action), do: {:error, :invalid_access_action}

  defp validate_action(action) when is_map(action) do
    with :ok <- exact_keys(action, @action_keys, :unknown_action_policy_field),
         :ok <- require(action, "requirement", &nonempty_string?/1, :invalid_access_requirement) do
      :ok
    end
  end

  defp validate_action(_), do: {:error, :invalid_access_requirement}

  defp validate_requirements(requirements) when is_map(requirements) do
    Enum.reduce_while(requirements, :ok, fn
      {name, requirement}, :ok when is_binary(name) and name != "" ->
        case validate_requirement(requirement) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      _, :ok ->
        {:halt, {:error, :invalid_access_requirements}}
    end)
  end

  defp validate_requirements(_), do: {:error, :invalid_access_requirements}

  defp validate_requirement(requirement) when is_map(requirement) do
    with :ok <- exact_keys(requirement, @requirement_keys, :unknown_requirement_field),
         :ok <-
           require(
             requirement,
             "credential_type",
             &valid_credential_type?/1,
             :unsupported_credential_type
           ),
         :ok <- validate_configuration_id(value(requirement, "credential_configuration_id")),
         :ok <-
           require(requirement, "trusted_issuers", &valid_issuers?/1, :invalid_trusted_issuers),
         :ok <- require(requirement, "claims", &valid_claims?/1, :invalid_claim_policy),
         :ok <-
           require(requirement, "holder_binding", &(&1 == "required"), :holder_binding_required),
         :ok <- require(requirement, "status", &valid_status?/1, :invalid_status_policy) do
      :ok
    end
  end

  defp validate_requirement(_), do: {:error, :invalid_access_requirements}

  defp validate_references(policy) do
    names = Map.keys(value(policy, "requirements"))

    references = [
      action_requirement(policy, :discovery),
      action_requirement(policy, :read),
      action_requirement(policy, :post),
      action_requirement(policy, :moderate)
    ]

    if Enum.all?(references, &(&1 in @built_in_requirements or &1 in names)),
      do: :ok,
      else: {:error, :unknown_access_requirement}
  end

  defp validate_visibility("end_to_end_encrypted") do
    if Application.get_env(:ansible_relay, :encrypted_boards_enabled, false),
      do: :ok,
      else: {:error, :encrypted_boards_not_enabled}
  end

  defp validate_visibility(value) when value in ["public", "host_visible"], do: :ok
  defp validate_visibility(_), do: {:error, :invalid_content_visibility}

  defp validate_privacy_combination(policy) do
    visibility = value(policy, "content_visibility")
    federation = value(policy, "federation")
    read = action_requirement(policy, :read)

    cond do
      visibility != "public" and federation != "disabled" ->
        {:error, :protected_board_federation_enabled}

      visibility == "public" and read not in ["public"] ->
        {:error, :credential_read_requires_nonpublic_visibility}

      true ->
        :ok
    end
  end

  defp action_requirement(policy, :discovery) do
    if value(policy, "discovery") == "public",
      do: "public",
      else: action_requirement(policy, :read)
  end

  defp action_requirement(policy, :moderate),
    do: value(value(policy, "moderate", %{"requirement" => "board_moderator"}), "requirement")

  defp action_requirement(policy, action),
    do: value(value(policy, Atom.to_string(action)), "requirement")

  defp evaluate_requirement(requirement, _requirements, _evidence)
       when requirement in @built_in_requirements,
       do: :ok

  defp evaluate_requirement(requirement, requirements, evidence) when is_map(evidence) do
    rule = Map.fetch!(requirements, requirement)

    cond do
      value(evidence, "credential_type") != value(rule, "credential_type") ->
        {:error, :credential_required}

      not is_nil(value(rule, "credential_configuration_id")) and
          value(evidence, "credential_configuration_id") !=
            value(rule, "credential_configuration_id") ->
        {:error, :credential_required}

      value(evidence, "issuer") not in value(rule, "trusted_issuers") ->
        {:error, :issuer_not_trusted}

      value(evidence, "holder_bound") != true ->
        {:error, :holder_binding_failed}

      value(evidence, "status") != "active" ->
        {:error, :credential_revoked}

      not claims_satisfied?(value(rule, "claims"), value(evidence, "claims", %{})) ->
        {:error, :claim_not_satisfied}

      true ->
        :ok
    end
  end

  defp evaluate_requirement(_requirement, _requirements, _evidence),
    do: {:error, :credential_required}

  defp claims_satisfied?(rules, claims) when is_map(claims) do
    Enum.all?(rules, fn rule ->
      value(rule, "op") == "equals" and value(claims, value(rule, "path")) == value(rule, "value")
    end)
  end

  defp valid_claims?(claims) when is_list(claims) and length(claims) in 1..4 do
    Enum.all?(claims, fn claim ->
      is_map(claim) and exact_keys(claim, @claim_keys, :invalid) == :ok and
        value(claim, "op") == "equals" and
        valid_claim_value?(value(claim, "path"), value(claim, "value"))
    end)
  end

  defp valid_claims?(_), do: false

  defp valid_claim_value?(path, value) when is_binary(path) do
    valid_claim_path?(path) and
      (is_boolean(value) or
         (is_binary(value) and byte_size(value) in 1..128) or
         (is_integer(value) and value >= 0 and value <= 1_000_000))
  end

  defp valid_claim_value?(_, _), do: false

  defp valid_claim_path?(path) do
    segments = String.split(path, ".", trim: true)

    length(segments) in 1..4 and
      Enum.all?(segments, &Regex.match?(~r/^[A-Za-z][A-Za-z0-9_]{0,63}$/, &1)) and
      Enum.all?(segments, &(not MapSet.member?(@prohibited_claims, String.downcase(&1))))
  end

  defp valid_credential_type?(type) when is_binary(type) do
    byte_size(type) in 3..128 and
      String.ends_with?(type, "Credential") and
      Regex.match?(~r/^[A-Za-z][A-Za-z0-9._:-]*Credential$/, type)
  end

  defp valid_credential_type?(_), do: false

  defp validate_configuration_id(nil), do: :ok

  defp validate_configuration_id(value)
       when is_binary(value) and byte_size(value) in 1..128 do
    if Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._:-]*$/, value),
      do: :ok,
      else: {:error, :invalid_credential_configuration_id}
  end

  defp validate_configuration_id(_), do: {:error, :invalid_credential_configuration_id}

  defp valid_issuers?(issuers) when is_list(issuers) and length(issuers) in 1..10,
    do:
      Enum.all?(
        issuers,
        &(is_binary(&1) and String.starts_with?(&1, "did:") and byte_size(&1) <= 256)
      )

  defp valid_issuers?(_), do: false

  defp valid_status?(status) when is_map(status) do
    exact_keys(status, @status_keys, :invalid) == :ok and value(status, "required") == true and
      is_integer(value(status, "max_age_seconds")) and value(status, "max_age_seconds") in 30..900
  end

  defp valid_status?(_), do: false
  defp valid_ttl?(ttl), do: is_integer(ttl) and ttl >= 60 and ttl <= 900
  defp nonempty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp exact_keys(map, allowed, error) do
    keys = map |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()
    if MapSet.subset?(keys, allowed), do: :ok, else: {:error, error}
  end

  defp require(map, key, validator, error) do
    case fetch_value(map, key) do
      {:ok, entry} -> if validator.(entry), do: :ok, else: {:error, error}
      :error -> {:error, error}
    end
  end

  defp fetch_value(map, key) do
    case Enum.find(map, fn {entry_key, _} -> to_string(entry_key) == key end) do
      nil -> :error
      {_entry_key, entry} -> {:ok, entry}
    end
  end

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map) do
    case fetch_value(map, key) do
      {:ok, entry} -> entry
      :error -> default
    end
  end

  defp value(_map, _key, default), do: default
end
