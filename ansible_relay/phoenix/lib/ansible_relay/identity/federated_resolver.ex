defmodule AnsibleRelay.Identity.FederatedResolver do
  @moduledoc """
  Cross-relay `did:elix` resolution (layered identity Phase C, v0).

  Resolution portability: a client asking *this* relay for a DID hosted on a
  *peer* relay still gets an answer. The trust model is "verify, don't trust the
  source": the local store is authoritative for what it anchored (verified at
  submit), but any answer fetched from a peer is re-verified here before it is
  returned —

    1. **Self-certification** — the DID must hash to the served anchor's own
       `identity_key` + `handle` (`DidElix.matches?`), so a peer cannot serve a
       forged identity under someone else's `did:elix`.
    2. **Signature** — the anchor `sig` must verify against that `identity_key`.

  Because both checks are over user-signed bytes, no relay has to trust another
  relay's word — the answer carries its own proof (Base Rule 1).

  ## v0 scope

  Self-certification proves the *genesis* binding (DID ⇔ genesis identity key).
  An identity that has since **rotated** its key no longer hashes to its current
  key, so a peer-served rotated anchor cannot be self-certified from the active
  anchor alone — resolving those across relays needs the full anchor chain and
  is a documented follow-up. v0 fails safe: a peer answer it cannot verify is
  rejected, never returned unverified. Locally-hosted identities (incl. rotated
  ones) resolve normally because they were verified at submit.
  """

  alias AnsibleRelay.{DidElix, SigVerifier}
  alias AnsibleRelay.Identity.AnchorStore

  @type source :: :local | {:peer, String.t()}

  @doc """
  Resolve a `did:elix` to a `{:ok, anchor_object, source}` or
  `{:error, :not_found | :locked}`.

  Options:
    * `:peers` — list of peer relay base URLs (default: `:federation_peers` config)
    * `:fetch` — `fn peer, did -> {:ok, object_map} | {:error, term} end`
      (default: HTTP GET of the peer's `/api/v1/identity/anchor/:did`)
  """
  @spec resolve(String.t(), keyword()) ::
          {:ok, map(), source()} | {:error, :not_found | :locked}
  def resolve(did, opts \\ []) when is_binary(did) do
    fetch = Keyword.get(opts, :fetch, &http_fetch_anchor/2)
    peers = Keyword.get(opts, :peers, peers())

    case AnchorStore.get_active(did) do
      {:ok, object} -> {:ok, object, :local}
      {:error, :locked} -> {:error, :locked}
      {:error, :not_found} -> resolve_via_peers(did, peers, fetch)
    end
  end

  defp resolve_via_peers(_did, [], _fetch), do: {:error, :not_found}

  defp resolve_via_peers(did, [peer | rest], fetch) do
    with {:ok, object} <- safe_fetch(fetch, peer, did),
         true <- is_map(object),
         true <- object["did"] == did,
         true <- verified?(object) do
      {:ok, object, {:peer, peer}}
    else
      _ -> resolve_via_peers(did, rest, fetch)
    end
  end

  defp safe_fetch(fetch, peer, did) do
    fetch.(peer, did)
  rescue
    _ -> {:error, :fetch_failed}
  end

  @doc """
  A peer-served anchor object is trustworthy iff it self-certifies (the DID is
  the hash of its `identity_key` + `handle`) AND its signature verifies. Both
  are over bytes the user signed, so the answer is verifiable independently.
  """
  def verified?(object) when is_map(object) do
    did = object["did"]
    identity_key = object["identity_key"]
    handle = object["handle"]
    custody = object["custody_class"] || "software"
    sig = object["sig"]

    DidElix.matches?(did, identity_key, handle, custody) and
      is_binary(sig) and sig != "" and
      SigVerifier.verify_ed25519(identity_key, AnchorStore.canonical_body(object), sig)
  end

  def verified?(_), do: false

  defp peers, do: Application.get_env(:ansible_relay, :federation_peers, [])

  # Best-effort HTTP fetch via OTP's built-in :httpc (no new dependency —
  # offline/closed-network constraint). Returns the decoded anchor object map.
  defp http_fetch_anchor(peer, did) do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    url = String.to_charlist("#{peer}/api/v1/identity/anchor/#{URI.encode(did)}")

    case :httpc.request(:get, {url, []}, [timeout: 5_000, connect_timeout: 3_000], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, object} when is_map(object) -> {:ok, object}
          _ -> {:error, :bad_response}
        end

      _ ->
        {:error, :unreachable}
    end
  end
end
