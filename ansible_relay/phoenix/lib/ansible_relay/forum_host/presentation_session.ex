defmodule AnsibleRelay.ForumHost.PresentationSession do
  @moduledoc "Single-use, board/audience/policy-bound OID4VP challenge storage."

  import Ecto.Query
  alias AnsibleRelay.Db.ForumHostVerificationNonce
  alias AnsibleRelay.Repo

  def issue(board, audience, action, opts \\ [])
      when action in [:discover, :read, :post, :moderate] do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    nonce = random()
    state = random()

    attrs = %{
      nonce_hash: hash(nonce),
      state_hash: hash(state),
      hosted_board_id: board.hosted_board_id,
      audience: audience,
      policy_version: board.access_policy_version,
      action: Atom.to_string(action),
      expires_at: DateTime.add(now, 120, :second)
    }

    with {:ok, _} <-
           %ForumHostVerificationNonce{}
           |> ForumHostVerificationNonce.changeset(attrs)
           |> Repo.insert() do
      {:ok, nonce, state}
    end
  end

  def consume(state, board_id, now \\ DateTime.utc_now()) do
    Repo.transaction(fn ->
      query =
        from(n in ForumHostVerificationNonce,
          where: n.state_hash == ^hash(state) and n.hosted_board_id == ^board_id,
          where: is_nil(n.consumed_at) and n.expires_at > ^now,
          lock: "FOR UPDATE"
        )

      case Repo.one(query) do
        nil ->
          Repo.rollback(:invalid_presentation_session)

        session ->
          session |> Ecto.Changeset.change(consumed_at: now) |> Repo.update!()
          session
      end
    end)
    |> case do
      {:ok, session} -> {:ok, session}
      {:error, reason} -> {:error, reason}
    end
  end

  def matches_nonce?(session, nonce),
    do: Plug.Crypto.secure_compare(session.nonce_hash, hash(nonce))

  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
