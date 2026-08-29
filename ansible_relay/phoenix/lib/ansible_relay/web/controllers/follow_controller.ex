defmodule AnsibleRelay.Web.Controllers.FollowController do
  @moduledoc "Authenticated follow-request and host-visible follower-feed reads."

  import Plug.Conn

  alias AnsibleRelay.{FollowAccess, IdentityCache, OpStore, WebauthnSync}

  def requests(conn, %{"target_did" => target_did}) do
    with :ok <- WebauthnSync.authorize(conn, target_did) do
      send_json(conn, 200, %{requests: FollowAccess.pending_requests(target_did)})
    else
      {:error, reason} -> send_json(conn, 401, %{error: Atom.to_string(reason)})
    end
  end

  def relationship(conn, params) do
    follower = params["follower_did"]
    target = params["target_did"]
    viewer = params["viewer_did"]

    with true <- is_binary(follower) and follower != "",
         true <- is_binary(target) and target != "",
         true <- viewer in [follower, target],
         :ok <- WebauthnSync.authorize(conn, viewer) do
      send_json(conn, 200, FollowAccess.relationship(follower, target))
    else
      {:error, reason} -> send_json(conn, 401, %{error: Atom.to_string(reason)})
      _ -> send_json(conn, 422, %{error: "invalid_follow_relationship"})
    end
  end

  def protected_delta(conn, author_did, params) do
    reader_did = params["reader"]

    with true <- is_binary(reader_did) and reader_did != "",
         :ok <- WebauthnSync.authorize(conn, reader_did),
         true <- FollowAccess.active_grant?(reader_did, author_did) do
      cursor = parse_int(params["cursor"], 0)
      limit = min(max(parse_int(params["limit"], 100), 1), 500)
      {visible, next_cursor, has_more} = scan(author_did, cursor, limit, [])

      send_json(conn, 200, %{
        ops: Enum.map(visible, &attach_verification/1),
        next_cursor: next_cursor,
        has_more: has_more,
        visibility: "host_visible",
        host_can_read: true
      })
    else
      {:error, reason} -> send_json(conn, 401, %{error: Atom.to_string(reason)})
      false -> send_json(conn, 403, %{error: "follow_grant_required"})
    end
  end

  defp scan(author_did, cursor, target, collected) do
    batch = OpStore.list_by_author(author_did, after_log_id: cursor, limit: 500)

    {matches, scanned_cursor, stopped_early} =
      Enum.reduce_while(batch, {collected, cursor, false}, fn op, {items, _last, _} ->
        next = if followers_content?(op), do: items ++ [op], else: items

        if length(next) >= target do
          {:halt, {next, op.log_id, true}}
        else
          {:cont, {next, op.log_id, false}}
        end
      end)

    cond do
      stopped_early -> {matches, scanned_cursor, true}
      length(batch) < 500 -> {matches, scanned_cursor, false}
      true -> scan(author_did, scanned_cursor, target, matches)
    end
  end

  defp followers_content?(%{entity_type: type, op_type: op_type, payload: payload})
       when type in ["murmur", "note"] and op_type in ["insert", "update", "delete"] do
    case FollowAccess.decode_payload(payload) do
      {:ok, %{"visibility" => "followers"}} -> true
      _ -> false
    end
  end

  defp followers_content?(_), do: false

  defp attach_verification(%{author_did: did} = op) do
    algorithm =
      case IdentityCache.get(did) do
        {:ok, entry} -> Map.get(entry, :signing_algorithm, "ed25519")
        _ -> "ed25519"
      end

    op
    |> Map.put(:public_key_hex, IdentityCache.public_key_hex(did))
    |> Map.put(:signing_algorithm, algorithm)
    |> Map.put(:canonical_author_did, AnsibleRelay.Identity.MigrationStore.canonical_did(did))
    |> Map.put(:reputation_tier, AnsibleRelay.DidAccountCache.reputation_tier(did))
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
