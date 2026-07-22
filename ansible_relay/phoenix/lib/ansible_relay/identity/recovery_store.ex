defmodule AnsibleRelay.Identity.RecoveryStore do
  @moduledoc "One-time, user-held recovery codes and reason-coded recovery audit."

  import Ecto.Query

  alias AnsibleRelay.{DidAccountCache, Repo}
  alias AnsibleRelay.Db.{IdentityAnchor, IdentityRecoveryAuditEvent, IdentityRecoveryCode}
  alias AnsibleRelay.Identity.AnchorStore

  @type_name "io.trisaura.identity.recoveryCodes"
  @max_codes 20

  def canonical_configuration(params) do
    entries = [
      {"type", @type_name},
      {"version", 1},
      {"did", params["did"]},
      {"generated_at", params["generated_at"]},
      {"code_hashes", params["code_hashes"]}
    ]

    "{" <>
      Enum.map_join(entries, ",", fn {key, value} ->
        Jason.encode!(key) <> ":" <> encode_configuration_value(key, value)
      end) <> "}"
  end

  defp encode_configuration_value("code_hashes", codes) when is_list(codes) do
    "[" <>
      Enum.map_join(codes, ",", fn code ->
        "{" <>
          Enum.map_join(["id", "hash", "hint"], ",", fn key ->
            Jason.encode!(key) <> ":" <> Jason.encode!(code[key])
          end) <> "}"
      end) <> "]"
  end

  defp encode_configuration_value(_key, value), do: Jason.encode!(value)

  def configure(params) do
    with :ok <- valid_configuration?(params),
         did when is_binary(did) <- params["did"],
         true <-
           DidAccountCache.verify_signature(
             did,
             canonical_configuration(params),
             params["signature"]
           ) || {:error, :invalid_signature} do
      now = DateTime.utc_now()

      Repo.transaction(fn ->
        Repo.update_all(
          from(c in IdentityRecoveryCode, where: c.did == ^did and c.state == "active"),
          set: [state: "revoked", revoked_at: now, updated_at: now]
        )

        Enum.each(params["code_hashes"], fn code ->
          %IdentityRecoveryCode{}
          |> IdentityRecoveryCode.changeset(%{
            did: did,
            code_id: code["id"],
            code_hash: String.downcase(code["hash"]),
            hint: code["hint"],
            state: "active"
          })
          |> Repo.insert!()
        end)

        audit!(did, "recovery_codes_configured", "user_configured", nil, %{
          "count" => length(params["code_hashes"])
        })
      end)

      {:ok, status(did)}
    else
      false -> {:error, :invalid_signature}
      {:error, _} = error -> error
      _ -> {:error, :malformed}
    end
  end

  def recover(anchor, code) when is_map(anchor) and is_binary(code) do
    did = anchor["did"]

    if is_binary(did) and did != "" do
      hash = hash_code(did, code)

      Repo.transaction(fn ->
        recovery_code =
          from(c in IdentityRecoveryCode,
            where: c.did == ^did and c.code_hash == ^hash and c.state == "active",
            lock: "FOR UPDATE"
          )
          |> Repo.one()

        if recovery_code == nil do
          Repo.rollback(:invalid_recovery_code)
        end

        case AnchorStore.submit(anchor, recovery_authorized: true) do
          {:ok, :pending, row} ->
            now = DateTime.utc_now()

            recovery_code
            |> Ecto.Changeset.change(state: "used", used_at: now)
            |> Repo.update!()

            audit!(did, "recovery_started", "recovery_code", row.anchor_cid, %{
              "code_id" => recovery_code.code_id,
              "grace_until" => DateTime.to_iso8601(row.grace_until)
            })

            {:pending, row}

          {:error, reason} ->
            Repo.rollback(reason)

          _ ->
            Repo.rollback(:invalid_recovery)
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :malformed}
    end
  end

  def recover(_anchor, _code), do: {:error, :malformed}

  def status(did) when is_binary(did) do
    counts =
      from(c in IdentityRecoveryCode,
        where: c.did == ^did,
        group_by: c.state,
        select: {c.state, count(c.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      "configured" => Map.get(counts, "active", 0) > 0,
      "remaining" => Map.get(counts, "active", 0),
      "used" => Map.get(counts, "used", 0),
      "revoked" => Map.get(counts, "revoked", 0)
    }
  end

  def audit(did) when is_binary(did) do
    anchors =
      from(a in IdentityAnchor,
        where: a.did == ^did,
        order_by: [desc: a.inserted_at],
        select: %{
          event_type: "identity_anchor",
          reason_code: a.reason,
          anchor_cid: a.anchor_cid,
          state: a.state,
          occurred_at: a.inserted_at
        }
      )
      |> Repo.all()

    events =
      from(e in IdentityRecoveryAuditEvent,
        where: e.did == ^did,
        order_by: [desc: e.inserted_at],
        select: %{
          event_type: e.event_type,
          reason_code: e.reason_code,
          anchor_cid: e.anchor_cid,
          state: nil,
          occurred_at: e.inserted_at
        }
      )
      |> Repo.all()

    event_anchor_cids =
      events
      |> Enum.map(& &1.anchor_cid)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    legacy_anchors =
      Enum.reject(anchors, fn anchor -> MapSet.member?(event_anchor_cids, anchor.anchor_cid) end)

    (legacy_anchors ++ events)
    |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
    |> Enum.map(fn event ->
      event
      |> Map.update!(:occurred_at, &DateTime.to_iso8601/1)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
  end

  def audit!(did, event_type, reason_code, anchor_cid, metadata \\ %{}) do
    %IdentityRecoveryAuditEvent{}
    |> IdentityRecoveryAuditEvent.changeset(%{
      did: did,
      event_type: event_type,
      reason_code: reason_code,
      anchor_cid: anchor_cid,
      metadata: metadata
    })
    |> Repo.insert!()
  end

  def hash_code(did, code) do
    normalized = code |> String.upcase() |> String.replace(~r/[^A-Z2-7]/, "")

    :crypto.hash(:sha256, "elix-recovery-code-v1\0" <> did <> "\0" <> normalized)
    |> Base.encode16(case: :lower)
  end

  defp valid_configuration?(params) do
    codes = params["code_hashes"]

    cond do
      params["type"] != @type_name -> {:error, :malformed}
      params["version"] != 1 -> {:error, :malformed}
      not is_binary(params["did"]) or params["did"] == "" -> {:error, :malformed}
      not valid_timestamp?(params["generated_at"]) -> {:error, :malformed}
      not is_binary(params["signature"]) -> {:error, :malformed}
      not is_list(codes) or codes == [] or length(codes) > @max_codes -> {:error, :malformed}
      not Enum.all?(codes, &valid_code_hash?/1) -> {:error, :malformed}
      length(Enum.uniq_by(codes, & &1["hash"])) != length(codes) -> {:error, :malformed}
      true -> :ok
    end
  end

  defp valid_code_hash?(code) when is_map(code) do
    is_binary(code["id"]) and byte_size(code["id"]) in 1..64 and
      is_binary(code["hint"]) and byte_size(code["hint"]) in 1..16 and
      is_binary(code["hash"]) and String.match?(code["hash"], ~r/\A[0-9a-fA-F]{64}\z/)
  end

  defp valid_code_hash?(_), do: false

  defp valid_timestamp?(value) when is_binary(value),
    do: match?({:ok, _, 0}, DateTime.from_iso8601(value))

  defp valid_timestamp?(_), do: false
end
