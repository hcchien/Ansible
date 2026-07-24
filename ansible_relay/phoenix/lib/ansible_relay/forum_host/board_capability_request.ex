defmodule AnsibleRelay.ForumHost.BoardCapabilityRequest do
  @moduledoc "Verifies device-bound proof-of-possession for a board capability request."

  import Plug.Conn
  alias AnsibleRelay.ForumHost.BoardCapability
  alias AnsibleRelay.Db.ForumHostBoardDpopProof
  alias AnsibleRelay.Repo
  alias AnsibleRelay.SigVerifier

  @max_clock_skew 60

  def authorize(conn, board_id, scope, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, token} <- header(conn, "x-elix-board-capability"),
         {:ok, encoded_jwk} <- header(conn, "x-elix-board-jwk"),
         {:ok, timestamp} <- header(conn, "x-elix-board-timestamp"),
         {:ok, request_nonce} <- header(conn, "x-elix-board-request-nonce"),
         {:ok, signature} <- header(conn, "x-elix-board-proof"),
         {:ok, unix} <- parse_unix(timestamp),
         true <- abs(DateTime.to_unix(now) - unix) <= @max_clock_skew,
         {:ok, jwk} <- decode_jwk(encoded_jwk),
         {:ok, public_hex, thumbprint} <- p256_material(jwk),
         canonical <- canonical_request(conn, board_id, scope, timestamp, request_nonce, token),
         true <- SigVerifier.verify_identity("p256-sha256", public_hex, canonical, signature),
         {:ok, grant} <- BoardCapability.authorize(token, board_id, scope, thumbprint),
         :ok <- consume_proof(token, request_nonce, timestamp, now) do
      {:ok, grant}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_board_capability}
    end
  end

  def device_thumbprint(jwk) when is_map(jwk) do
    case p256_material(jwk) do
      {:ok, _public_hex, thumbprint} -> {:ok, thumbprint}
      {:error, reason} -> {:error, reason}
    end
  end

  def device_thumbprint(_), do: {:error, :invalid_board_capability}

  defp canonical_request(conn, board_id, scope, timestamp, nonce, token) do
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    Enum.join(
      [conn.method, conn.request_path, board_id, scope, timestamp, nonce, token_hash],
      "\n"
    )
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value] when value != "" -> {:ok, value}
      _ -> {:error, :board_capability_required}
    end
  end

  defp parse_unix(value) do
    case Integer.parse(value) do
      {unix, ""} -> {:ok, unix}
      _ -> {:error, :invalid_board_capability}
    end
  end

  defp decode_jwk(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, %{} = jwk} <- Jason.decode(json) do
      {:ok, jwk}
    else
      _ -> {:error, :invalid_board_capability}
    end
  end

  defp p256_material(%{"kty" => "EC", "crv" => "P-256", "x" => x, "y" => y} = jwk) do
    with {:ok, x_bytes} <- Base.url_decode64(x, padding: false),
         {:ok, y_bytes} <- Base.url_decode64(y, padding: false),
         true <- byte_size(x_bytes) == 32 and byte_size(y_bytes) == 32 do
      public_hex = Base.encode16(<<4, x_bytes::binary, y_bytes::binary>>, case: :lower)

      thumbprint =
        Jason.encode!(%{"crv" => jwk["crv"], "kty" => jwk["kty"], "x" => x, "y" => y})
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.url_encode64(padding: false)

      {:ok, public_hex, thumbprint}
    else
      _ -> {:error, :invalid_board_capability}
    end
  end

  defp p256_material(_), do: {:error, :invalid_board_capability}

  defp consume_proof(token, nonce, timestamp, now) do
    capability_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    proof_hash =
      :crypto.hash(:sha256, capability_hash <> "\x00" <> timestamp <> "\x00" <> nonce)
      |> Base.encode16(case: :lower)

    attrs = %{
      proof_hash: proof_hash,
      capability_hash: capability_hash,
      expires_at: DateTime.add(now, @max_clock_skew, :second)
    }

    changeset = ForumHostBoardDpopProof.changeset(%ForumHostBoardDpopProof{}, attrs)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, proof} ->
        row = %{
          proof_hash: proof.proof_hash,
          capability_hash: proof.capability_hash,
          expires_at: proof.expires_at,
          inserted_at: now
        }

        case Repo.insert_all(ForumHostBoardDpopProof, [row],
               on_conflict: :nothing,
               conflict_target: [:proof_hash]
             ) do
          {1, _} -> :ok
          {0, _} -> {:error, :board_capability_replay}
        end

      {:error, _} ->
        {:error, :invalid_board_capability}
    end
  end
end
