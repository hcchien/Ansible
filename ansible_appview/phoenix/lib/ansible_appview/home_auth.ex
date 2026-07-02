defmodule AnsibleAppview.HomeAuth do
  @moduledoc """
  Minimal signed-request authentication for the personalized home feed
  (`GET /api/v1/home`). The home feed discloses a reader's follow graph, so a
  caller may only read their OWN home feed — it must prove control of the DID it
  asks for.

  This reuses the stack's existing identity primitive — an Ed25519 signature
  over a canonical JSON payload (`AnsibleAppview.SigningPayload.canonical_json/1`,
  the same canonicalization the relay/app/AppView already use for op signatures)
  — rather than inventing a new auth scheme. The AppView has no online DID
  resolver, but it already stores each author's public key on every folded op
  (`feed_items.public_key_hex`), so it can verify the presented key is genuinely
  bound to the claimed DID.

  ## Request contract

  The caller signs the canonical payload

      {"did": <reader-did>, "path": "/api/v1/home", "ts": <unix-seconds>}

  with the DID's Ed25519 signing key and presents:

    * `x-reader-did`         — the reader DID (must equal the `reader` query param)
    * `x-reader-public-key`  — hex Ed25519 public key
    * `x-reader-timestamp`   — unix seconds, must be within `@max_skew_seconds`
    * `x-reader-signature`   — hex Ed25519 signature over the canonical payload

  Verification (all required):

    1. `did` header equals the `reader` query param (can only read your own feed);
    2. timestamp is present and within the freshness window (replay bound);
    3. the signature verifies over the canonical payload with the presented key;
    4. the presented key is bound to that DID in our projection — there is at
       least one folded op authored by `did` carrying this exact
       `public_key_hex`. This stops a caller presenting a self-minted keypair for
       someone else's DID.

  Returns `:ok`, `{:error, :unauthorized}` (missing/mismatched/expired/forged),
  or `{:error, :unknown_reader}` (no key binding on record for the DID — 403).
  """

  import Ecto.Query

  alias AnsibleAppview.{SigningPayload, SigVerifier}
  alias AnsibleAppview.Db.FeedItem

  @path "/api/v1/home"
  @max_skew_seconds 300

  defp read_repo, do: Application.get_env(:ansible_appview, :read_repo, AnsibleAppview.Repo)

  @doc """
  Authorize a home-feed request. `headers` is a map of lower-cased header name to
  value (as `Plug.Conn`'s `req_headers` provides). `reader` is the query param.
  """
  @spec authorize(map(), String.t()) :: :ok | {:error, :unauthorized | :unknown_reader}
  def authorize(headers, reader) when is_map(headers) and is_binary(reader) do
    did = headers["x-reader-did"]
    pubkey = headers["x-reader-public-key"]
    ts = headers["x-reader-timestamp"]
    sig = headers["x-reader-signature"]

    with true <- is_binary(did) and did == reader,
         {:ok, ts_int} <- parse_ts(ts),
         true <- fresh?(ts_int),
         true <- is_binary(pubkey) and is_binary(sig),
         true <- signature_ok?(did, pubkey, ts_int, sig) do
      if key_bound?(did, pubkey) do
        :ok
      else
        {:error, :unknown_reader}
      end
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authorize(_headers, _reader), do: {:error, :unauthorized}

  @doc "The canonical bytes a caller must sign for a home request at `ts`."
  def challenge(did, ts) do
    SigningPayload.canonical_json(%{"did" => did, "path" => @path, "ts" => ts})
  end

  defp signature_ok?(did, pubkey, ts_int, sig) do
    SigVerifier.verify_ed25519(pubkey, challenge(did, ts_int), sig)
  end

  # The presented key must be the one the DID actually signs ops with, as
  # recorded on any folded op. Without this an attacker could sign the challenge
  # with a self-generated keypair and pass it off as the victim's DID.
  defp key_bound?(did, pubkey) do
    read_repo().exists?(
      from(f in FeedItem, where: f.author_did == ^did and f.public_key_hex == ^pubkey)
    )
  end

  defp parse_ts(nil), do: :error
  defp parse_ts(ts) when is_integer(ts), do: {:ok, ts}

  defp parse_ts(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {n, _} -> {:ok, n}
      :error -> :error
    end
  end

  defp fresh?(ts_int) do
    abs(System.os_time(:second) - ts_int) <= @max_skew_seconds
  end
end
