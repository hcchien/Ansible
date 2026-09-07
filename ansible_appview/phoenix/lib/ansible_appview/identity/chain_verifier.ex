defmodule AnsibleAppview.Identity.ChainVerifier do
  @moduledoc "Independently verify self-certification and every authority transition."
  alias AnsibleAppview.{DidElix, SigVerifier}
  alias AnsibleAppview.Identity.AnchorEncoding, as: AnchorStore

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
end
