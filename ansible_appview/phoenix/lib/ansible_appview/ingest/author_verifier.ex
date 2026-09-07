defmodule AnsibleAppview.Ingest.AuthorVerifier do
  @moduledoc "Independent author authority, signed content and WebAuthn verification."
  alias AnsibleAppview.{SigVerifier, SigningPayload}
  alias AnsibleAppview.Identity.ChainVerifier

  def verify(op, payload) do
    with {:ok, expiry, _} <- DateTime.from_iso8601(op["anchor_expires_at"] || ""),
         true <- DateTime.compare(expiry, DateTime.utc_now()) == :gt,
         {:ok, keys} <- authority_keys(op) do
      valid =
        if is_map(payload["web_author_proof"]),
          do: web_valid?(op, payload, keys),
          else:
            signed?(
              epoch_keys(
                op,
                payload["updatedAt"] || payload["createdAt"] || payload["publishedAt"],
                keys
              ),
              SigningPayload.build(op),
              op["signature"]
            )

      if valid,
        do: {:ok, %{expiry | microsecond: {elem(expiry.microsecond, 0), 6}}},
        else: {:error, :bad_signature}
    else
      false -> {:error, :expired_anchor}
      {:error, :unbound_author} -> {:error, :unbound_author}
      _ -> {:error, :missing_anchor}
    end
  rescue
    _ -> {:error, :bad_signature}
  end

  def authority_keys(%{"author_did" => did, "identity_chain" => chain})
      when is_list(chain) and length(chain) in 1..128 do
    if ChainVerifier.verified_chain?(did, chain) do
      {:ok, Enum.map(chain, &{&1["identity_key_algorithm"] || "ed25519", &1["identity_key"]})}
    else
      {:error, :unbound_author}
    end
  rescue
    _ -> {:error, :unbound_author}
  end

  # Legacy self-certifying Ed25519 did:key needs no resolver assertion.
  def authority_keys(%{"author_did" => "did:key:z" <> encoded}) do
    with <<0xED, 1, key::binary-size(32)>> <- decode58(encoded) do
      {:ok, [{"ed25519", Base.encode16(key, case: :lower)}]}
    else
      _ -> {:error, :unbound_author}
    end
  end

  def authority_keys(_), do: {:error, :unbound_author}

  # A historical key is eligible only in its signed anchor epoch. Without a
  # signed content timestamp use only the current authority, never all old keys.
  defp epoch_keys(op, at, keys) do
    chain = op["identity_chain"] || []

    case {chain, DateTime.from_iso8601(at || "")} do
      {[_ | _], {:ok, timestamp, _}} ->
        eligible =
          Enum.filter(chain, fn anchor ->
            case DateTime.from_iso8601(anchor["created_at"] || "") do
              {:ok, created, _} -> DateTime.compare(created, timestamp) != :gt
              _ -> false
            end
          end)

        case List.last(eligible) do
          nil -> []
          anchor -> [{anchor["identity_key_algorithm"] || "ed25519", anchor["identity_key"]}]
        end

      {[_ | _], _} ->
        [List.last(keys)]

      _ ->
        keys
    end
  end

  def bind_provenance(op, payload) do
    {:ok, keys} = authority_keys(op)
    proof = payload["web_author_proof"]

    {bytes, signature, at} =
      if is_map(proof) do
        {canonical_json(proof["delegation"]), proof["delegation_signature"],
         proof["delegation"]["issued_at"]}
      else
        {SigningPayload.build(op), op["signature"],
         payload["updatedAt"] || payload["createdAt"] || payload["publishedAt"]}
      end

    {algorithm, key} =
      Enum.find(epoch_keys(op, at, keys), fn {a, k} ->
        SigVerifier.verify_identity(a, k, bytes, signature)
      end)

    op
    |> Map.put("public_key_hex", key)
    |> Map.put("signing_algorithm", algorithm)
    |> Map.put("canonical_author_did", verified_canonical_did(op, keys))
  end

  defp verified_canonical_did(op, keys) do
    evidence = op["identity_migration"]

    with true <- is_map(evidence),
         true <- evidence["type"] == "io.trisaura.identity.migration" and evidence["version"] == 1,
         true <- evidence["legacy_did"] == op["author_did"],
         true <- evidence["v1_did"] == op["canonical_author_did"],
         chain when is_list(chain) and length(chain) in 1..128 <- evidence["target_chain"],
         true <- hd(chain)["schema_version"] == 4,
         true <- ChainVerifier.verified_chain?(evidence["v1_did"], chain),
         body <- migration_body(evidence),
         true <-
           signed?(epoch_keys(op, evidence["created_at"], keys), body, evidence["legacy_sig"]),
         target_keys <-
           Enum.map(chain, &{&1["identity_key_algorithm"] || "ed25519", &1["identity_key"]}),
         true <-
           signed?(
             epoch_keys(%{"identity_chain" => chain}, evidence["created_at"], target_keys),
             body,
             evidence["v1_sig"]
           ) do
      evidence["v1_did"]
    else
      _ -> op["author_did"]
    end
  end

  def migration_body(evidence) do
    ~s({"type":"io.trisaura.identity.migration","version":1,"legacy_did":) <>
      Jason.encode!(evidence["legacy_did"]) <>
      ~s(,"v1_did":) <>
      Jason.encode!(evidence["v1_did"]) <>
      ~s(,"created_at":) <>
      Jason.encode!(evidence["created_at"]) <> "}"
  end

  defp signed?(keys, bytes, signature),
    do:
      Enum.any?(keys, fn {algorithm, key} ->
        SigVerifier.verify_identity(algorithm, key, bytes, signature)
      end)

  defp web_valid?(op, payload, keys) do
    proof = payload["web_author_proof"]
    operation = payload["web_operation"]
    delegation = proof["delegation"]
    hash = payload["web_operation_hash"]

    with true <- is_map(operation) and is_map(delegation),
         true <- proof["scheme"] == "webauthn-p256-sha256",
         true <-
           operation["type"] == "io.trisaura.webPublicationOperation" and
             operation["version"] == 1,
         true <- hash == sha256(canonical_json(operation)) and hash == proof["operation_hash"],
         true <- operation["payload_hash"] == sha256(canonical_json(operation["payload"])),
         true <-
           operation["operation_id"] == op["op_id"] and
             operation["author_did"] == op["author_did"],
         true <-
           operation["entity_type"] == op["entity_type"] and
             operation["entity_id"] == op["entity_id"],
         true <- action_type(operation["action"]) == op["op_type"],
         true <- operation["visibility"] in ["public", "unlisted"],
         true <-
           projected_payload(operation) ==
             Map.drop(
               payload,
               ~w(web_author_proof web_operation web_operation_hash web_host_receipt)
             ),
         true <-
           delegation["type"] == "io.trisaura.identity.webCredentialDelegation" and
             delegation["version"] == 1,
         true <-
           delegation["subject_did"] == op["author_did"] and
             delegation["delegation_id"] == proof["delegation_id"],
         true <-
           is_list(delegation["allowed_actions"]) and
             operation["action"] in delegation["allowed_actions"],
         true <-
           signed?(
             epoch_keys(op, delegation["issued_at"], keys),
             canonical_json(delegation),
             proof["delegation_signature"]
           ),
         true <- valid_times?(operation, delegation),
         {:ok, credential_id} <- decode64(proof["credential_id"]),
         true <- sha256(credential_id) == delegation["credential_id_hash"],
         {:ok, attestation} <- decode64(proof["registration_attestation"]),
         true <- sha256(attestation) == delegation["attestation_sha256"],
         {:ok, %{"authData" => registration_data}, <<>>} <- Wax.Utils.CBOR.decode(attestation),
         {:ok, registered} <- Wax.AuthenticatorData.decode(registration_data),
         %{credential_id: ^credential_id, credential_public_key: cose} <-
           registered.attested_credential_data,
         true <- cose[3] == -7,
         true <- registered.rp_id_hash == :crypto.hash(:sha256, delegation["rp_id"]),
         true <- valid_origin?(delegation),
         {:ok, client_data} <- decode64(proof["client_data_json"]),
         {:ok, auth_data} <- decode64(proof["authenticator_data"]),
         {:ok, signature} <- decode64(proof["signature"]),
         challenge <-
           Wax.new_authentication_challenge(
             origin: delegation["origin"],
             rp_id: delegation["rp_id"],
             user_verification: "required",
             bytes: :crypto.hash(:sha256, "elix.web-publication.v1\0" <> hash)
           ),
         {:ok, _} <-
           Wax.authenticate(
             Base.encode64(credential_id),
             auth_data,
             signature,
             client_data,
             challenge,
             [{Base.encode64(credential_id), cose}]
           ) do
      true
    else
      _ -> false
    end
  end

  defp valid_origin?(delegation) do
    uri = URI.parse(delegation["origin"])
    rp = delegation["rp_id"]

    uri.scheme == "https" and is_binary(uri.host) and is_binary(rp) and rp != "" and
      is_nil(uri.userinfo) and uri.path in [nil, "", "/"] and is_nil(uri.query) and
      is_nil(uri.fragment) and
      (uri.host == rp or String.ends_with?(uri.host, "." <> rp))
  end

  # Evaluate the signed operation time, not ingest time: a rebuild must retain
  # historically authorized content after a delegation expires. This verifier
  # establishes historical cryptographic consistency only. Authority.Witness
  # separately requires current authority on first observation and persists the
  # immutable observation for rebuilds; source times/receipts cannot replace it.
  defp valid_times?(operation, delegation) do
    with {:ok, created, _} <- DateTime.from_iso8601(operation["created_at"] || ""),
         {:ok, expires, _} <- DateTime.from_iso8601(operation["expires_at"] || ""),
         {:ok, issued, _} <- DateTime.from_iso8601(delegation["issued_at"] || ""),
         {:ok, revoked, _} <- DateTime.from_iso8601(delegation["expires_at"] || "") do
      DateTime.compare(created, issued) != :lt and DateTime.compare(expires, revoked) != :gt and
        DateTime.diff(expires, created) in 1..300 and
        DateTime.diff(revoked, issued) in 1..31_536_000 and
        DateTime.compare(created, DateTime.add(DateTime.utc_now(), 300)) != :gt and
        is_binary(operation["nonce"]) and byte_size(operation["nonce"]) >= 16
    else
      _ -> false
    end
  end

  defp action_type(action)
       when action in ["forum.publish", "forum.reply", "forum.react", "forum.moderate"],
       do: "insert"

  defp action_type("forum.edit"), do: "update"
  defp action_type("forum.delete"), do: "delete"
  defp action_type(_), do: nil

  defp projected_payload(operation) do
    payload = operation["payload"]

    payload =
      if operation["action"] == "forum.react",
        do:
          payload
          |> Map.put_new("targetType", "post")
          |> Map.put("targetId", operation["parent_id"]),
        else: payload

    payload
    |> Map.put("boardId", operation["board_id"])
    |> Map.put("threadId", operation["parent_id"])
    |> Map.put("createdAt", operation["created_at"])
    |> Map.put("publishedAt", operation["created_at"])
    |> Map.put("visibility", operation["visibility"])
    |> Map.put("federate", operation["federate"])
  end

  def canonical_json(value) when is_map(value),
    do:
      "{" <>
        (value
         |> Enum.sort_by(&elem(&1, 0))
         |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> canonical_json(v) end)) <>
        "}"

  def canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  def canonical_json(value), do: Jason.encode!(value)
  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp decode64(value) when is_binary(value) and byte_size(value) <= 131_072,
    do: Base.url_decode64(value, padding: false)

  defp decode64(_), do: :error

  defp decode58(value) when byte_size(value) <= 100 do
    alphabet = ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    number =
      Enum.reduce(String.to_charlist(value), 0, fn c, acc ->
        acc * 58 + (Enum.find_index(alphabet, &(&1 == c)) || raise ArgumentError)
      end)

    :binary.copy(<<0>>, value |> String.to_charlist() |> Enum.take_while(&(&1 == ?1)) |> length()) <>
      :binary.encode_unsigned(number)
  end
end
