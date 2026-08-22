defmodule AnsibleRelay.Identity.FederatedResolver do
  @moduledoc """
  Cross-relay `did:elix` resolution (layered identity Phase C).

  Resolution portability: a client asking *this* relay for a DID hosted on a
  *peer* relay still gets an answer. The trust model is "verify, don't trust the
  source": the local store is authoritative for what it anchored (verified at
  submit), but any answer fetched from a peer is re-verified here before it is
  returned —

    1. **Self-certification** — legacy genesis anchors bind the DID to their
       key and handle; v1 genesis anchors bind it to the immutable commitment.
    2. **Full-chain verification** — canonical CIDs, links, current-key
       signatures, device attestations, reason semantics, immutable v1
       commitment, and previous-authority transition proofs all verify.

  Because both checks are over user-signed bytes, no relay has to trust another
  relay's word — the answer carries its own proof (Base Rule 1).

  A valid historical chain can still be replayed by an availability source.
  Callers that need rollback detection must compare independent Relays or pin a
  previously observed active CID; cryptographic chain verification alone cannot
  prove that a source disclosed the newest signed successor.
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
      (default: HTTP GET of the peer's `/api/v1/identity/chain/:did`)
  """
  @spec resolve(String.t(), keyword()) ::
          {:ok, map(), source()} | {:error, :not_found | :locked}
  def resolve(did, opts \\ []) when is_binary(did) do
    fetch = Keyword.get(opts, :fetch, &http_fetch_chain/2)
    peers = Keyword.get(opts, :peers, peers())

    case AnchorStore.get_chain(did) do
      {:ok, objects} -> {:ok, List.last(objects), :local}
      {:error, :locked} -> {:error, :locked}
      {:error, :not_found} -> resolve_via_peers(did, peers, fetch)
      {:error, :invalid_chain} -> {:error, :not_found}
    end
  end

  defp resolve_via_peers(_did, [], _fetch), do: {:error, :not_found}

  defp resolve_via_peers(did, [peer | rest], fetch) do
    with {:ok, response} <- safe_fetch(fetch, peer, did),
         {:ok, object} <- verified_active(did, response) do
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
  A peer-served legacy genesis object is trustworthy iff it self-certifies and
  its signature verifies. Rotated and v1 identities use `verified_chain?/2`.
  """
  def verified?(object) when is_map(object) do
    genesis_verified?(object) and anchor_verified?(object)
  end

  def verified?(_), do: false

  @doc "Verify a peer-served v1 genesis-to-active chain and return its active anchor."
  def verified_chain?(did, objects) when is_binary(did) and is_list(objects) do
    case objects do
      [genesis | rest] ->
        genesis["did"] == did and genesis["reason"] == "initial" and
          is_nil(genesis["prev_anchor_cid"]) and genesis_verified?(genesis) and
          anchor_verified?(genesis) and successors_verified?(genesis, rest)

      _ ->
        false
    end
  end

  def verified_chain?(_, _), do: false

  defp verified_active(did, %{"anchors" => objects}) when is_list(objects) do
    if verified_chain?(did, objects), do: {:ok, List.last(objects)}, else: {:error, :invalid}
  end

  # Compatibility with v0 peers is limited to a self-certified genesis.
  defp verified_active(did, object) when is_map(object) do
    if object["did"] == did and object["reason"] == "initial" and verified?(object),
      do: {:ok, object},
      else: {:error, :invalid}
  end

  defp verified_active(_, _), do: {:error, :invalid}

  defp genesis_verified?(%{"schema_version" => version} = object) when version >= 4 do
    commitment = object["genesis_commitment"]

    is_map(commitment) and commitment["genesis_key"] == object["identity_key"] and
      DidElix.matches_v1?(object["did"], commitment)
  end

  defp genesis_verified?(object) do
    DidElix.matches?(
      object["did"],
      object["identity_key"],
      object["handle"],
      object["custody_class"] || "software",
      object["identity_key_algorithm"] || "ed25519"
    )
  end

  defp anchor_verified?(object) do
    algorithm = object["identity_key_algorithm"] || "ed25519"
    body = AnchorStore.canonical_body(object)

    is_binary(object["sig"]) and
      SigVerifier.verify_identity(algorithm, object["identity_key"], body, object["sig"]) and
      Enum.all?(object["devices"] || [], fn device ->
        SigVerifier.verify_identity(
          algorithm,
          object["identity_key"],
          AnchorStore.device_attestation_message(device),
          device["attestation_sig"]
        )
      end) and
      (not is_binary(object["anchor_cid"]) or
         object["anchor_cid"] == AnchorStore.compute_cid(object))
  end

  defp successors_verified?(_previous, []), do: true

  defp successors_verified?(previous, [current | rest]) do
    body = AnchorStore.canonical_body(current)

    authorization =
      if current["reason"] == "recovery",
        do: current["recovery_proof"],
        else: current["device_sig"]

    commitment_ok =
      if previous["schema_version"] >= 4 do
        current["schema_version"] == 4 and
          current["genesis_commitment"] == previous["genesis_commitment"] and
          DidElix.matches_v1?(current["did"], current["genesis_commitment"])
      else
        current["schema_version"] < 4
      end

    reason_ok =
      case current["reason"] do
        "rotation" ->
          {current["identity_key_algorithm"] || "ed25519", current["identity_key"]} !=
            {previous["identity_key_algorithm"] || "ed25519", previous["identity_key"]}

        "recovery" ->
          current["schema_version"] < 4 or
            {current["identity_key_algorithm"] || "ed25519", current["identity_key"]} !=
              {previous["identity_key_algorithm"] || "ed25519", previous["identity_key"]}

        "device_change" ->
          {current["identity_key_algorithm"] || "ed25519", current["identity_key"]} ==
            {previous["identity_key_algorithm"] || "ed25519", previous["identity_key"]} and
            current["custody_class"] == previous["custody_class"]

        _ ->
          false
      end

    authority_ok =
      SigVerifier.verify_identity(
        previous["identity_key_algorithm"] || "ed25519",
        previous["identity_key"],
        body,
        authorization
      ) or
        (current["reason"] != "rotation" and
           Enum.any?(previous["devices"] || [], fn device ->
             SigVerifier.verify_ed25519(device["device_key"], body, authorization)
           end))

    current["did"] == previous["did"] and
      current["prev_anchor_cid"] == AnchorStore.compute_cid(previous) and
      current["reason"] in ["rotation", "recovery", "device_change"] and commitment_ok and
      reason_ok and anchor_verified?(current) and authority_ok and
      successors_verified?(current, rest)
  end

  defp peers, do: Application.get_env(:ansible_relay, :federation_peers, [])

  # Best-effort HTTP fetch via OTP's built-in :httpc (no new dependency —
  # offline/closed-network constraint). Returns the decoded anchor object map.
  defp http_fetch_chain(peer, did) do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    url = String.to_charlist("#{peer}/api/v1/identity/chain/#{URI.encode(did)}")

    case :httpc.request(:get, {url, []}, [timeout: 5_000, connect_timeout: 3_000],
           body_format: :binary
         ) do
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
