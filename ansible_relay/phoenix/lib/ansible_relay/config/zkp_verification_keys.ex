defmodule AnsibleRelay.Config.ZkpVerificationKeys do
  @moduledoc """
  Boot-time validation of `:zkp_verification_keys` for production releases.
  Called from `config/runtime.exs` (prod branch only).

  `config/config.exs` ships dev placeholder entries
  (`sha256:dev-vk-hash-placeholder`, `sha256:dev-passport-v1-placeholder`) so
  local anchoring flows work without real circuit artifacts. Those hashes are
  not trust anchors and must never be active in a production release.

  The Phase 1 ZKP challenge/anchor flow is currently retired (no code path
  consumes `:zkp_verification_keys` today — see IdentityController's moduledoc),
  so production boots **fail closed with no active keys**: any future consumer
  finds an empty registry and rejects every proof, instead of silently trusting
  a placeholder baked into the image. Operators enable the feature explicitly
  by setting `ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS` to a JSON array of audited
  verification-key entries.
  """

  @hash_format ~r/\Asha256:[0-9a-f]{64}\z/
  @valid_statuses %{"active" => :active, "retired" => :retired}

  @doc """
  Returns the production value for `:zkp_verification_keys`.

  * `nil` (env var unset) — the ZKP verification path is not live. Returns `[]`,
    overriding the dev placeholders from `config.exs` (fail closed).
  * JSON string — parsed and validated via `parse!/1`; raises on any
    malformed or placeholder entry so the release refuses to boot.
  """
  def load_prod!(nil), do: []
  def load_prod!(json) when is_binary(json), do: parse!(json)

  @doc """
  Parses `ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS`: a non-empty JSON array of
  `{"version": "...", "hash": "sha256:<64 lowercase hex>", "status": "active" | "retired"}`.

  Raises `ArgumentError` with an actionable message on malformed JSON, missing
  fields, an unknown status, or a hash that is not a real sha256 digest
  (which is exactly what the `sha256:dev-*-placeholder` sentinels are).
  """
  def parse!(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, [_ | _] = entries} ->
        Enum.map(entries, &validate_entry!/1)

      {:ok, _other} ->
        raise ArgumentError, """
        ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS must be a non-empty JSON array of
        {"version", "hash", "status"} objects. To run with the ZKP verification
        path disabled (the default), leave the variable unset.
        """

      {:error, _} ->
        raise ArgumentError, """
        ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS is not valid JSON.
        Expected a JSON array like:
        [{"version":"passport_v1_groth16_bn254","hash":"sha256:<64 hex>","status":"active"}]
        """
    end
  end

  defp validate_entry!(%{"version" => version, "hash" => hash, "status" => status})
       when is_binary(version) and is_binary(hash) and is_binary(status) do
    if version == "" do
      raise ArgumentError,
            "ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS entry has an empty \"version\"."
    end

    unless Regex.match?(@hash_format, hash) do
      raise ArgumentError, """
      ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS entry #{inspect(version)} has hash
      #{inspect(hash)}, which is not "sha256:" + 64 lowercase hex chars.
      Dev placeholders (e.g. "sha256:dev-vk-hash-placeholder") are rejected in
      production — pin the audited circuit verification-key digest instead.
      """
    end

    case Map.fetch(@valid_statuses, status) do
      {:ok, status_atom} ->
        %{version: version, hash: hash, status: status_atom}

      :error ->
        raise ArgumentError, """
        ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS entry #{inspect(version)} has status
        #{inspect(status)}; expected "active" or "retired".
        """
    end
  end

  defp validate_entry!(other) do
    raise ArgumentError, """
    ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS entry #{inspect(other)} is malformed.
    Each entry must be {"version": string, "hash": "sha256:<64 hex>", "status": "active" | "retired"}.
    """
  end
end
