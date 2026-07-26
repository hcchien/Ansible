defmodule AnsibleRelay.ActivityPub.InboundHttpSignature do
  @moduledoc """
  Verifies inbound ActivityPub HTTP Signatures against the exact request bytes.

  HTTP Signatures authenticate remote transport only. A valid result never
  upgrades an ActivityPub actor to an Elix DID or trust tier.
  """

  import Ecto.Query

  alias AnsibleRelay.{Db.ActivityPubInboundReceipt, Repo}

  @required_signed ["(request-target)", "host", "date", "digest"]
  @default_skew_seconds 300

  def verify(conn, activity, opts \\ [])

  def verify(conn, activity, opts) when is_map(activity) do
    raw_body = conn.private[:raw_body] || ""
    headers = normalized_headers(conn)
    signature_header = headers["signature"] || headers["authorization"]
    actor_uri = activity["actor"]

    with true <- is_binary(actor_uri) and actor_uri != "",
         {:ok, signature} <- parse_signature(signature_header),
         :ok <- required_headers(signature.headers),
         :ok <- verify_digest(headers["digest"], raw_body),
         :ok <- verify_date(headers["date"], Keyword.get(opts, :now, DateTime.utc_now()), opts),
         {:ok, document} <- fetch_key_document(signature.key_id, opts),
         {:ok, public_key_pem, owner} <- resolve_key(document, signature.key_id),
         true <- owner == actor_uri,
         :ok <- verify_crypto(conn, headers, signature, public_key_pem),
         :ok <- consume_replay(signature, actor_uri, opts) do
      {:ok, %{actor_uri: actor_uri, key_id: signature.key_id}}
    else
      false -> {:error, :actor_key_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :invalid_http_signature}
    end
  end

  def verify(_, _, _), do: {:error, :invalid_http_signature}

  defp parse_signature(nil), do: {:error, :missing_http_signature}

  defp parse_signature("Signature " <> value), do: parse_signature(value)

  defp parse_signature(value) when is_binary(value) do
    attrs =
      Regex.scan(~r/([a-zA-Z]+)="([^"]*)"/, value)
      |> Map.new(fn [_, key, entry] -> {String.downcase(key), entry} end)

    with key_id when is_binary(key_id) and key_id != "" <- attrs["keyid"],
         encoded when is_binary(encoded) and encoded != "" <- attrs["signature"],
         {:ok, bytes} <- Base.decode64(encoded),
         headers when is_binary(headers) <- attrs["headers"],
         algorithm when algorithm in ["rsa-sha256", "hs2019"] <-
           String.downcase(attrs["algorithm"] || "") do
      {:ok,
       %{
         key_id: key_id,
         bytes: bytes,
         headers: String.split(String.downcase(headers), ~r/\s+/, trim: true)
       }}
    else
      _ -> {:error, :malformed_http_signature}
    end
  end

  defp required_headers(headers) do
    if Enum.all?(@required_signed, &(&1 in headers)),
      do: :ok,
      else: {:error, :unsigned_required_header}
  end

  defp verify_digest(nil, _), do: {:error, :missing_digest}

  defp verify_digest("SHA-256=" <> encoded, raw_body) do
    expected = :crypto.hash(:sha256, raw_body)

    case Base.decode64(encoded) do
      {:ok, actual} when byte_size(actual) == byte_size(expected) ->
        if Plug.Crypto.secure_compare(actual, expected),
          do: :ok,
          else: {:error, :digest_mismatch}

      _ ->
        {:error, :invalid_digest}
    end
  end

  defp verify_digest(_, _), do: {:error, :unsupported_digest}

  defp verify_date(nil, _, _), do: {:error, :missing_date}

  defp verify_date(value, %DateTime{} = now, opts) do
    skew = Keyword.get(opts, :clock_skew_seconds, @default_skew_seconds)

    with {:ok, request_time} <- parse_http_date(value),
         true <- abs(DateTime.diff(now, request_time, :second)) <= skew do
      :ok
    else
      false -> {:error, :stale_http_signature}
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_http_date(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{year, month, day}, {hour, minute, second}} ->
        DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, second), "Etc/UTC")

      _ ->
        {:error, :invalid_date}
    end
  rescue
    _ -> {:error, :invalid_date}
  end

  defp fetch_key_document(key_id, opts) do
    fetcher = Keyword.get(opts, :key_fetcher, &default_key_fetcher/1)
    host_validator = Keyword.get(opts, :host_validator, &public_host/1)

    with %URI{scheme: "https", host: host} when is_binary(host) <- URI.parse(key_id),
         :ok <- host_validator.(host),
         {:ok, %{} = document} <- fetcher.(String.split(key_id, "#", parts: 2) |> hd()) do
      {:ok, document}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_key_id}
    end
  end

  defp resolve_key(%{"publicKey" => keys}, key_id) do
    keys
    |> List.wrap()
    |> Enum.find(&(&1["id"] == key_id))
    |> case do
      %{"publicKeyPem" => pem, "owner" => owner}
      when is_binary(pem) and is_binary(owner) ->
        {:ok, pem, owner}

      _ ->
        {:error, :key_not_found}
    end
  end

  defp resolve_key(_, _), do: {:error, :key_not_found}

  defp verify_crypto(conn, headers, signature, pem) do
    with {:ok, key} <- decode_public_key(pem),
         {:ok, signing_string} <- signing_string(conn, headers, signature.headers),
         true <- :public_key.verify(signing_string, :sha256, signature.bytes, key) do
      :ok
    else
      false -> {:error, :bad_http_signature}
      {:error, _} = error -> error
      _ -> {:error, :bad_http_signature}
    end
  end

  defp signing_string(conn, headers, signed_headers) do
    target =
      conn.request_path <>
        if(conn.query_string in [nil, ""], do: "", else: "?" <> conn.query_string)

    signed_headers
    |> Enum.reduce_while([], fn
      "(request-target)", acc ->
        value = "#{String.downcase(conn.method)} #{target}"
        {:cont, ["(request-target): " <> value | acc]}

      name, acc ->
        case headers[name] do
          nil -> {:halt, {:error, :signed_header_missing}}
          value -> {:cont, ["#{name}: #{value}" | acc]}
        end
    end)
    |> case do
      {:error, _} = error -> error
      lines -> {:ok, lines |> Enum.reverse() |> Enum.join("\n")}
    end
  end

  defp consume_replay(signature, actor_uri, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
    ttl = Keyword.get(opts, :replay_ttl_seconds, @default_skew_seconds * 2)
    hash = :crypto.hash(:sha256, signature.bytes) |> Base.encode16(case: :lower)

    Repo.delete_all(from(r in ActivityPubInboundReceipt, where: r.expires_at < ^now))

    %ActivityPubInboundReceipt{}
    |> ActivityPubInboundReceipt.changeset(%{
      signature_hash: hash,
      actor_uri: actor_uri,
      key_id: signature.key_id,
      expires_at: DateTime.add(now, ttl, :second)
    })
    |> Repo.insert()
    |> case do
      {:ok, _} ->
        :ok

      {:error, %{errors: errors}} ->
        if Keyword.has_key?(errors, :signature_hash),
          do: {:error, :replayed_http_signature},
          else: {:error, :replay_store_failed}
    end
  end

  defp decode_public_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      _ -> {:error, :invalid_public_key}
    end
  rescue
    _ -> {:error, :invalid_public_key}
  end

  defp default_key_fetcher(url) do
    case :httpc.request(
           :get,
           {String.to_charlist(url), [{~c"accept", ~c"application/activity+json"}]},
           [timeout: 5_000, connect_timeout: 3_000, autoredirect: false],
           body_format: :binary
         ) do
      {:ok, {{_http, 200, _}, _headers, body}} when byte_size(body) <= 1_000_000 ->
        case Jason.decode(body) do
          {:ok, %{} = document} -> {:ok, document}
          _ -> {:error, :invalid_actor_document}
        end

      _ ->
        {:error, :actor_document_unavailable}
    end
  end

  defp public_host(host) do
    with {:ok, addresses} <- :inet.getaddrs(String.to_charlist(host), :inet),
         true <- addresses != [] and Enum.all?(addresses, &public_ipv4?/1) do
      :ok
    else
      _ -> {:error, :unsafe_key_host}
    end
  end

  defp public_ipv4?({10, _, _, _}), do: false
  defp public_ipv4?({127, _, _, _}), do: false
  defp public_ipv4?({169, 254, _, _}), do: false
  defp public_ipv4?({172, second, _, _}) when second in 16..31, do: false
  defp public_ipv4?({192, 168, _, _}), do: false
  defp public_ipv4?({0, _, _, _}), do: false
  defp public_ipv4?({first, _, _, _}) when first >= 224, do: false
  defp public_ipv4?({_a, _b, _c, _d}), do: true

  defp normalized_headers(conn) do
    conn.req_headers
    |> Enum.reduce(%{}, fn {name, value}, acc ->
      Map.update(acc, String.downcase(name), value, &(&1 <> ", " <> value))
    end)
    |> Map.put_new("host", authority(conn))
  end

  defp authority(%{host: host, scheme: scheme, port: port})
       when (scheme == :http and port == 80) or (scheme == :https and port == 443),
       do: host

  defp authority(%{host: host, port: port}), do: "#{host}:#{port}"
end
