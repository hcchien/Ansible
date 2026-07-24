defmodule AnsibleRelay.ForumHost.BitstringStatusChecker do
  @moduledoc "Fail-closed W3C Bitstring Status List verifier for membership credentials."

  alias AnsibleRelay.ForumHost.TrustedMembershipIssuer

  @max_age_seconds 300
  @max_response_bytes 1_000_000

  def check(entries, now), do: check(entries, now, [])

  def check(entries, now, opts) when is_list(entries) do
    fetcher = Keyword.get(opts, :fetcher, &fetch/1)

    Enum.reduce_while(entries, :active, fn entry, _status ->
      case check_entry(entry, now, fetcher) do
        :active -> {:cont, :active}
        status when status in [:revoked, :suspended] -> {:halt, status}
        _ -> {:halt, :unavailable}
      end
    end)
  end

  def check(%{"type" => "TrisAuraStatusEndpoint2024", "id" => url}, _now, opts)
      when is_binary(url) do
    fetcher = Keyword.get(opts, :json_fetcher, &fetch_json/1)

    with true <- TrustedMembershipIssuer.status_url_allowed?(url),
         {:ok, %{"status" => status}} <- fetcher.(url) do
      case status do
        "active" -> :active
        "revoked" -> :revoked
        "suspended" -> :suspended
        _ -> :unavailable
      end
    else
      _ -> :unavailable
    end
  end

  def check(_, _now, _opts), do: :unavailable

  defp check_entry(entry, now, fetcher) when is_map(entry) do
    purpose = entry["statusPurpose"]
    url = entry["statusListCredential"]

    with true <- purpose in ["revocation", "suspension"],
         {index, ""} <- Integer.parse(to_string(entry["statusListIndex"])),
         true <- index >= 0,
         true <- TrustedMembershipIssuer.status_url_allowed?(url),
         {:ok, compact} <- fetcher.(url),
         {:ok, header, claims, signed, signature} <- decode_jwt(compact),
         true <- header["alg"] == "EdDSA" and header["typ"] == "JWT",
         {:ok, public_key} <- TrustedMembershipIssuer.resolve(claims["iss"], header["kid"]),
         true <- :crypto.verify(:eddsa, :none, signed, signature, [public_key, :ed25519]),
         true <- fresh?(claims, now),
         %{} = vc <- claims["vc"],
         true <- vc["id"] == url,
         %{} = subject <- vc["credentialSubject"],
         true <- subject["statusPurpose"] == purpose,
         {:ok, compressed} <- decode_multibase(subject["encodedList"]),
         {:ok, bits} <- gunzip(compressed),
         true <- index < byte_size(bits) * 8 do
      if bit_set?(bits, index), do: set_status(purpose), else: :active
    else
      _ -> :unavailable
    end
  rescue
    _ -> :unavailable
  end

  defp check_entry(_, _, _), do: :unavailable

  defp fresh?(claims, now) do
    iat = claims["iat"]

    is_integer(iat) and iat <= DateTime.to_unix(now) + 30 and
      iat >= DateTime.to_unix(now) - @max_age_seconds
  end

  defp decode_jwt(compact) do
    with [encoded_header, encoded_claims, encoded_signature] <- String.split(compact, "."),
         {:ok, header_json} <- Base.url_decode64(encoded_header, padding: false),
         {:ok, claims_json} <- Base.url_decode64(encoded_claims, padding: false),
         {:ok, signature} <- Base.url_decode64(encoded_signature, padding: false),
         {:ok, %{} = header} <- Jason.decode(header_json),
         {:ok, %{} = claims} <- Jason.decode(claims_json) do
      {:ok, header, claims, encoded_header <> "." <> encoded_claims, signature}
    else
      _ -> {:error, :invalid_status_list}
    end
  end

  defp decode_multibase("u" <> encoded), do: Base.url_decode64(encoded, padding: false)
  defp decode_multibase(_), do: {:error, :invalid_status_list}

  defp gunzip(compressed) when byte_size(compressed) <= @max_response_bytes do
    bits = :zlib.gunzip(compressed)
    if byte_size(bits) == 16_384, do: {:ok, bits}, else: {:error, :invalid_status_list}
  end

  defp gunzip(_), do: {:error, :invalid_status_list}

  defp bit_set?(bits, index) do
    byte = :binary.at(bits, div(index, 8))
    Bitwise.band(byte, Bitwise.bsl(1, 7 - rem(index, 8))) != 0
  end

  defp set_status("revocation"), do: :revoked
  defp set_status("suspension"), do: :suspended

  defp fetch(url) do
    case :httpc.request(
           :get,
           {String.to_charlist(url), [{~c"accept", ~c"application/vc+jwt"}]},
           [timeout: 5_000, connect_timeout: 3_000],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, body}} when byte_size(body) <= @max_response_bytes ->
        {:ok, body}

      _ ->
        {:error, :status_unavailable}
    end
  end

  defp fetch_json(url) do
    case :httpc.request(
           :get,
           {String.to_charlist(url), [{~c"accept", ~c"application/json"}]},
           [timeout: 5_000, connect_timeout: 3_000],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, body}} when byte_size(body) <= @max_response_bytes ->
        Jason.decode(body)

      _ ->
        {:error, :status_unavailable}
    end
  end
end
