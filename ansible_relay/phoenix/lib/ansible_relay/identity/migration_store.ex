defmodule AnsibleRelay.Identity.MigrationStore do
  @moduledoc """
  Explicit, dual-signed legacy did:elix to v1 bindings.

  The Relay stores public evidence only. Both currently active identity keys
  sign the same canonical body, so a resolver can verify the relationship
  without treating the Relay as the identity authority.
  """

  import Ecto.Query

  alias AnsibleRelay.{Repo, SigVerifier}
  alias AnsibleRelay.Db.DidElixMigration
  alias AnsibleRelay.Identity.AnchorStore

  @migration_type "io.trisaura.identity.migration"

  def canonical_body(object) when is_map(object) do
    ~s({"type":"#{@migration_type}","version":1,"legacy_did":) <>
      Jason.encode!(object["legacy_did"]) <>
      ~s(,"v1_did":) <>
      Jason.encode!(object["v1_did"]) <>
      ~s(,"created_at":) <>
      Jason.encode!(object["created_at"]) <>
      "}"
  end

  def submit(params) when is_map(params) do
    legacy_did = params["legacy_did"]
    v1_did = params["v1_did"]
    legacy_sig = params["legacy_sig"]
    v1_sig = params["v1_sig"]

    with :ok <- validate_shape(params),
         {:ok, _} <- AnchorStore.get_chain(legacy_did),
         {:ok, v1_chain} <- AnchorStore.get_chain(v1_did),
         true <- List.first(v1_chain)["schema_version"] == 4 || {:error, :not_v1},
         legacy when not is_nil(legacy) <- AnchorStore.active_anchor(legacy_did),
         v1 when not is_nil(v1) <- AnchorStore.active_anchor(v1_did),
         body = canonical_body(params),
         true <-
           SigVerifier.verify_identity(
             legacy.identity_key_algorithm || "ed25519",
             legacy.identity_key,
             body,
             legacy_sig
           ) || {:error, :invalid_signature},
         true <-
           SigVerifier.verify_identity(
             v1.identity_key_algorithm || "ed25519",
             v1.identity_key,
             body,
             v1_sig
           ) || {:error, :invalid_signature},
         {:ok, created_at, 0} <- DateTime.from_iso8601(params["created_at"]),
         {:ok, row} <-
           %DidElixMigration{}
           |> DidElixMigration.changeset(%{
             legacy_did: legacy_did,
             v1_did: v1_did,
             canonical_body: body,
             legacy_sig: legacy_sig,
             v1_sig: v1_sig,
             created_at: created_at
           })
           |> Repo.insert() do
      {:ok, to_object(row)}
    else
      {:error, :not_found} -> {:error, :did_not_found}
      {:error, :locked} -> {:error, :locked}
      {:error, :invalid_chain} -> {:error, :invalid_chain}
      {:error, %Ecto.Changeset{}} -> {:error, :conflict}
      {:error, _} = error -> error
      nil -> {:error, :did_not_found}
      _ -> {:error, :malformed}
    end
  end

  def get(legacy_did) when is_binary(legacy_did) do
    case Repo.get(DidElixMigration, legacy_did) do
      nil -> {:error, :not_found}
      row -> {:ok, to_object(row)}
    end
  end

  def aliases_for(did) when is_binary(did) do
    Repo.all(
      from(m in DidElixMigration,
        where: m.legacy_did == ^did or m.v1_did == ^did,
        select: {m.legacy_did, m.v1_did}
      )
    )
    |> Enum.map(fn
      {^did, v1_did} -> v1_did
      {legacy_did, ^did} -> legacy_did
    end)
  end

  defp validate_shape(params) do
    legacy_did = params["legacy_did"]
    v1_did = params["v1_did"]

    expected_keys =
      MapSet.new(~w(type version legacy_did v1_did created_at legacy_sig v1_sig))

    actual_keys = params |> Map.keys() |> MapSet.new()

    cond do
      actual_keys != expected_keys ->
        {:error, :malformed}

      params["type"] != @migration_type or params["version"] != 1 ->
        {:error, :malformed}

      not is_binary(legacy_did) or
          not String.match?(legacy_did, ~r/\Adid:elix:[a-z2-7]{10,}\z/) ->
        {:error, :malformed}

      String.match?(legacy_did, ~r/\Adid:elix:z[a-z2-7]{52}\z/) ->
        {:error, :not_legacy}

      not is_binary(v1_did) or
          not String.match?(v1_did, ~r/\Adid:elix:z[a-z2-7]{52}\z/) ->
        {:error, :not_v1}

      legacy_did == v1_did ->
        {:error, :malformed}

      not is_binary(params["legacy_sig"]) or params["legacy_sig"] == "" ->
        {:error, :malformed}

      not is_binary(params["v1_sig"]) or params["v1_sig"] == "" ->
        {:error, :malformed}

      not canonical_timestamp?(params["created_at"]) ->
        {:error, :malformed}

      true ->
        :ok
    end
  end

  defp canonical_timestamp?(value) when is_binary(value) do
    String.match?(
      value,
      ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:(?!000)\d{3})?Z\z/
    ) and
      match?({:ok, _datetime, 0}, DateTime.from_iso8601(value))
  end

  defp canonical_timestamp?(_), do: false

  defp to_object(row) do
    row.canonical_body
    |> Jason.decode!()
    |> Map.merge(%{
      "legacy_sig" => row.legacy_sig,
      "v1_sig" => row.v1_sig,
      "canonical_body" => row.canonical_body
    })
  end
end
