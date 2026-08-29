defmodule AnsibleRelay.ForumHost.BoardCapability do
  @moduledoc """
  Issues and authorizes short-lived, opaque, board-scoped capabilities.

  Only a SHA-256 hash is stored. Authorization binds the exact Forum Host
  audience, board, policy version, scope, pairwise holder and device key.
  """

  import Ecto.Query

  alias AnsibleRelay.Db.{ForumHostBoard, ForumHostBoardAccessGrant}
  alias AnsibleRelay.Repo

  @prefix "elix_board_v1_"
  @allowed_scopes ~w(discover read post moderate analyze key:read)

  def issue(
        %ForumHostBoard{} = board,
        pairwise_subject,
        device_key_thumbprint,
        scopes,
        opts \\ []
      ) do
    ttl = Keyword.get(opts, :ttl_seconds, board.access_policy["capability_ttl_seconds"] || 300)
    audience = Keyword.get(opts, :audience, AnsibleRelay.ForumHost.Store.base_url())
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with :ok <- validate_issue(pairwise_subject, device_key_thumbprint, scopes, ttl, audience),
         token <- @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
         attrs <- %{
           capability_hash: hash(token),
           # This column has a foreign key to the durable hosted-board key.
           # DPoP and the public capability protocol use canonical_board_id,
           # while storage retains this internal relation during migration.
           hosted_board_id: board.hosted_board_id,
           pairwise_subject_hash: hash(pairwise_subject),
           device_key_thumbprint: device_key_thumbprint,
           audience: audience,
           policy_version: board.access_policy_version,
           scopes: Enum.uniq(scopes),
           expires_at: DateTime.add(now, ttl, :second)
         },
         {:ok, grant} <-
           %ForumHostBoardAccessGrant{}
           |> ForumHostBoardAccessGrant.changeset(attrs)
           |> Repo.insert() do
      {:ok, token, grant}
    end
  end

  def authorize(token, board_id, scope, device_key_thumbprint, opts \\ []) do
    audience = Keyword.get(opts, :audience, AnsibleRelay.ForumHost.Store.base_url())
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with true <- is_binary(token) and String.starts_with?(token, @prefix),
         %ForumHostBoardAccessGrant{} = grant <- active_grant(hash(token), now),
         %ForumHostBoard{} = board <- resolve_board(board_id),
         true <- grant.hosted_board_id == board.hosted_board_id,
         true <- grant.audience == audience,
         true <- grant.policy_version == board.access_policy_version,
         true <- scope in grant.scopes,
         true <- secure_equal(grant.device_key_thumbprint, device_key_thumbprint) do
      {:ok, grant}
    else
      nil -> {:error, :capability_expired}
      false -> {:error, :invalid_board_capability}
      _ -> {:error, :invalid_board_capability}
    end
  end

  @doc "Returns the canonical external identifier for a hosted board."
  def canonical_board_id(%ForumHostBoard{board_id: board_id})
      when is_integer(board_id) and board_id > 0,
      do: Integer.to_string(board_id)

  def canonical_board_id(%ForumHostBoard{hosted_board_id: hosted_board_id}), do: hosted_board_id

  @doc "Resolves a route or legacy hosted key to its canonical external board id."
  def canonical_board_id_for(board_id) do
    case resolve_board(board_id) do
      %ForumHostBoard{} = board -> canonical_board_id(board)
      nil -> nil
    end
  end

  def revoke_board(board_id, reason) when is_binary(reason) and reason != "" do
    now = DateTime.utc_now()
    canonical_id = canonical_board_id_for(board_id)

    from(g in ForumHostBoardAccessGrant,
      where: g.hosted_board_id in ^Enum.uniq([board_id, canonical_id]) and is_nil(g.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now, revocation_reason: reason])
  end

  defp resolve_board(board_id) when is_binary(board_id) do
    case Integer.parse(board_id) do
      {numeric_id, ""} when numeric_id > 0 ->
        Repo.get_by(ForumHostBoard, board_id: numeric_id) || Repo.get(ForumHostBoard, board_id)

      _ ->
        Repo.get(ForumHostBoard, board_id)
    end
  end

  defp resolve_board(_board_id), do: nil

  defp active_grant(capability_hash, now) do
    from(g in ForumHostBoardAccessGrant,
      where:
        g.capability_hash == ^capability_hash and is_nil(g.revoked_at) and g.expires_at > ^now
    )
    |> Repo.one()
  end

  defp validate_issue(subject, device, scopes, ttl, audience) do
    cond do
      not (is_binary(subject) and subject != "") ->
        {:error, :invalid_pairwise_subject}

      not (is_binary(device) and byte_size(device) in 32..256) ->
        {:error, :invalid_device_key}

      not (is_binary(audience) and audience != "") ->
        {:error, :invalid_audience}

      not (is_list(scopes) and scopes != [] and Enum.all?(scopes, &(&1 in @allowed_scopes))) ->
        {:error, :invalid_scope}

      not (is_integer(ttl) and ttl in 60..900) ->
        {:error, :invalid_capability_ttl}

      true ->
        :ok
    end
  end

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp secure_equal(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right),
       do: Plug.Crypto.secure_compare(left, right)

  defp secure_equal(_, _), do: false
end
