defmodule AnsibleRelay.ForumHost.BoardVpVerifier do
  @moduledoc """
  Verifies the Elix OID4VP JWT-VP profile for board access.

  The VP is ES256 holder-signed and embeds exactly one compact jwt_vc_json.
  Holder JWK, VC `cnf`, subject, audience and nonce must all bind together.
  Issuer key resolution and status checking are injected boundaries so tests
  do not need network access and production can enforce pinned issuer manifests.
  """

  alias AnsibleRelay.ForumHost.BoardAccessPolicy
  import Bitwise

  @vp_typ "openid4vp+jwt"
  def verify(compact, policy, requirement_name, nonce, audience, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    issuer_resolver = Keyword.fetch!(opts, :issuer_resolver)
    status_checker = Keyword.fetch!(opts, :status_checker)
    board_id = Keyword.fetch!(opts, :board_id)
    forum_host_id = Keyword.fetch!(opts, :forum_host_id)

    with {:ok, header, claims, signed, signature} <- decode_jwt(compact),
         :ok <- validate_vp_header(header),
         :ok <- validate_vp_claims(claims, nonce, audience, now),
         {:ok, holder_key} <- p256_key(header["jwk"]),
         true <-
           :crypto.verify(:ecdsa, :sha256, signed, jose_signature_to_der(signature), [
             holder_key,
             :secp256r1
           ]),
         {:ok, credential} <- embedded_credential(claims),
         {:ok, vc_header, vc_claims, vc_signed, vc_signature} <- decode_jwt(credential),
         :ok <- validate_vc_header(vc_header),
         :ok <- validate_holder_binding(claims, vc_claims, header["jwk"]),
         :ok <- validate_vc_time(vc_claims, now),
         {:ok, issuer_key} <- issuer_resolver.(vc_claims["iss"], vc_header["kid"]),
         true <- verify_ed25519(issuer_key, vc_signed, vc_signature),
         {:ok, rule} <- credential_rule(policy, requirement_name),
         {:ok, vc, credential_type} <- credential_payload(vc_claims, rule),
         :ok <- validate_configuration(vc, rule),
         :ok <- validate_board_binding(vc, forum_host_id, board_id),
         :ok <- validate_status(status_checker, vc, now),
         evidence <- evidence(vc_claims, vc, credential_type, rule),
         :ok <- BoardAccessPolicy.evaluate_for_requirement(policy, requirement_name, evidence) do
      {:ok,
       %{
         pairwise_subject: vc_claims["sub"],
         device_key_thumbprint: jwk_thumbprint(header["jwk"]),
         evidence: evidence
       }}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :holder_binding_failed}
      _ -> {:error, :invalid_presentation}
    end
  rescue
    error ->
      if Keyword.get(opts, :debug, false),
        do: reraise(error, __STACKTRACE__),
        else: {:error, :invalid_presentation}
  end

  def nonce(compact) do
    with {:ok, _header, claims, _signed, _signature} <- decode_jwt(compact),
         nonce when is_binary(nonce) and nonce != "" <- claims["nonce"] do
      {:ok, nonce}
    else
      _ -> {:error, :invalid_presentation}
    end
  end

  defp decode_jwt(compact) when is_binary(compact) do
    case String.split(compact, ".") do
      [encoded_header, encoded_claims, encoded_signature] ->
        with {:ok, header_json} <- Base.url_decode64(encoded_header, padding: false),
             {:ok, claims_json} <- Base.url_decode64(encoded_claims, padding: false),
             {:ok, signature} <- Base.url_decode64(encoded_signature, padding: false),
             {:ok, header} <- Jason.decode(header_json),
             {:ok, claims} <- Jason.decode(claims_json),
             true <- is_map(header) and is_map(claims) do
          {:ok, header, claims, encoded_header <> "." <> encoded_claims, signature}
        else
          _ -> {:error, :invalid_presentation}
        end

      _ ->
        {:error, :invalid_presentation}
    end
  end

  defp decode_jwt(_), do: {:error, :invalid_presentation}

  defp validate_vp_header(%{"alg" => "ES256", "typ" => @vp_typ, "jwk" => %{} = jwk}) do
    if MapSet.new(Map.keys(jwk)) == MapSet.new(~w(kty crv x y)),
      do: :ok,
      else: {:error, :invalid_presentation}
  end

  defp validate_vp_header(_), do: {:error, :invalid_presentation}

  defp validate_vp_claims(claims, nonce, audience, now) do
    iat = claims["iat"]

    cond do
      claims["aud"] != audience ->
        {:error, :wrong_audience}

      claims["nonce"] != nonce ->
        {:error, :wrong_nonce}

      not (is_binary(claims["sub"]) and claims["sub"] != "") ->
        {:error, :holder_binding_failed}

      not is_integer(iat) ->
        {:error, :invalid_presentation}

      iat > DateTime.to_unix(now) + 30 or iat < DateTime.to_unix(now) - 300 ->
        {:error, :invalid_presentation}

      true ->
        :ok
    end
  end

  defp validate_vc_header(%{"alg" => "EdDSA", "typ" => "JWT", "kid" => kid}) when is_binary(kid),
    do: :ok

  defp validate_vc_header(_), do: {:error, :invalid_credential}

  defp embedded_credential(%{"vp" => %{"verifiableCredential" => [credential]}})
       when is_binary(credential), do: {:ok, credential}

  defp embedded_credential(_), do: {:error, :invalid_credential}

  defp validate_holder_binding(vp_claims, vc_claims, holder_jwk) do
    if vc_claims["sub"] == vp_claims["sub"] and get_in(vc_claims, ["cnf", "jwk"]) == holder_jwk,
      do: :ok,
      else: {:error, :holder_binding_failed}
  end

  defp validate_vc_time(claims, now) do
    unix = DateTime.to_unix(now)

    if is_integer(claims["nbf"]) and is_integer(claims["exp"]) and claims["nbf"] <= unix + 30 and
         claims["exp"] > unix,
       do: :ok,
       else: {:error, :credential_expired}
  end

  defp credential_rule(policy, requirement_name) do
    case get_in(policy, ["requirements", requirement_name]) do
      %{} = rule -> {:ok, rule}
      _ -> {:error, :credential_required}
    end
  end

  defp credential_payload(%{"vc" => %{} = vc}, rule) do
    types = vc["type"] || []
    expected = rule["credential_type"]

    if is_binary(expected) and expected in types,
      do: {:ok, vc, expected},
      else: {:error, :credential_required}
  end

  defp credential_payload(_, _), do: {:error, :invalid_credential}

  defp validate_configuration(vc, rule) do
    case rule["credential_configuration_id"] do
      nil ->
        :ok

      expected ->
        actual =
          vc["credentialConfigurationId"] ||
            get_in(vc, ["credentialSubject", "credential_configuration_id"])

        if actual == expected,
          do: :ok,
          else: {:error, :credential_required}
    end
  end

  defp validate_board_binding(
         %{"credentialSubject" => %{"forum_host_id" => forum_host_id, "board_id" => board_id}},
         forum_host_id,
         board_id
       )
       when is_binary(forum_host_id) and forum_host_id != "" and is_binary(board_id) and board_id != "",
       do: :ok

  defp validate_board_binding(%{"credentialSubject" => subject}, _forum_host_id, _board_id)
       when is_map(subject) do
    if Map.has_key?(subject, "board_id") or Map.has_key?(subject, "forum_host_id"),
      do: {:error, :wrong_board},
      else: :ok
  end

  defp validate_board_binding(_, _, _), do: {:error, :invalid_credential}

  defp validate_status(checker, vc, now) do
    case checker.(vc["credentialStatus"], now) do
      :active -> :ok
      :suspended -> {:error, :credential_revoked}
      :revoked -> {:error, :credential_revoked}
      _ -> {:error, :credential_status_unavailable}
    end
  end

  defp evidence(claims, vc, credential_type, rule) do
    %{
      "credential_type" => credential_type,
      "credential_configuration_id" => rule["credential_configuration_id"],
      "issuer" => claims["iss"],
      "holder_bound" => true,
      "status" => "active",
      "claims" => vc["credentialSubject"] || %{}
    }
  end

  defp p256_key(%{"kty" => "EC", "crv" => "P-256", "x" => x, "y" => y}) do
    with {:ok, x_bytes} <- Base.url_decode64(x, padding: false),
         {:ok, y_bytes} <- Base.url_decode64(y, padding: false),
         true <- byte_size(x_bytes) == 32 and byte_size(y_bytes) == 32 do
      {:ok, <<4, x_bytes::binary, y_bytes::binary>>}
    else
      _ -> {:error, :holder_binding_failed}
    end
  end

  defp p256_key(_), do: {:error, :holder_binding_failed}

  defp verify_ed25519(<<_::binary-size(32)>> = key, signed, <<_::binary-size(64)>> = signature),
    do: :crypto.verify(:eddsa, :none, signed, signature, [key, :ed25519])

  defp verify_ed25519(_, _, _), do: false

  @doc false
  def jose_signature_to_der(<<r::binary-size(32), s::binary-size(32)>>),
    do: der_sequence(der_integer(r) <> der_integer(s))

  def jose_signature_to_der(_), do: <<>>

  defp der_integer(bytes) do
    stripped = String.trim_leading(bytes, <<0>>)
    unsigned = if stripped == <<>>, do: <<0>>, else: stripped

    value =
      if (:binary.first(unsigned) &&& 0x80) != 0, do: <<0, unsigned::binary>>, else: unsigned

    <<2, byte_size(value), value::binary>>
  end

  defp der_sequence(value), do: <<48, byte_size(value), value::binary>>

  defp jwk_thumbprint(jwk) do
    Jason.encode!(%{"crv" => jwk["crv"], "kty" => jwk["kty"], "x" => jwk["x"], "y" => jwk["y"]})
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
