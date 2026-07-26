defmodule AnsibleRelay.ActivityPub.HttpSignature do
  @moduledoc """
  Creates RSA-SHA256 HTTP Signatures for ActivityPub inbox delivery.

  The relay owns the transport key. User identity proofs authorize creation of
  an activity but never leave the relay as key material or credential claims.
  """

  @signed_headers ["(request-target)", "host", "date", "digest", "content-type"]

  def headers(method, url, body, actor_uri, opts \\ []) do
    private_key_pem =
      Keyword.get(opts, :private_key_pem) ||
        Application.get_env(:ansible_relay, :activity_pub_private_key_pem)

    with pem when is_binary(pem) and pem != "" <- private_key_pem,
         {:ok, private_key} <- decode_private_key(pem),
         %URI{host: host} = uri when is_binary(host) <- URI.parse(url) do
      date = :httpd_util.rfc1123_date() |> List.to_string()
      digest = "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())
      host_header = host_header(uri)
      target = request_target(uri)

      signing_string =
        [
          "(request-target): #{String.downcase(to_string(method))} #{target}",
          "host: #{host_header}",
          "date: #{date}",
          "digest: #{digest}",
          "content-type: application/activity+json"
        ]
        |> Enum.join("\n")

      signature = :public_key.sign(signing_string, :sha256, private_key) |> Base.encode64()

      signature_header =
        ~s(keyId="#{actor_uri}#main-key",algorithm="rsa-sha256",headers="#{Enum.join(@signed_headers, " ")}",signature="#{signature}")

      {:ok,
       [
         {~c"host", String.to_charlist(host_header)},
         {~c"date", String.to_charlist(date)},
         {~c"digest", String.to_charlist(digest)},
         {~c"content-type", ~c"application/activity+json"},
         {~c"signature", String.to_charlist(signature_header)}
       ]}
    else
      nil -> {:error, :activity_pub_signing_key_missing}
      "" -> {:error, :activity_pub_signing_key_missing}
      _ -> {:error, :invalid_activity_pub_signing_configuration}
    end
  end

  defp decode_private_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      _ -> {:error, :invalid_private_key}
    end
  rescue
    _ -> {:error, :invalid_private_key}
  end

  defp host_header(%URI{host: host, port: nil}), do: host
  defp host_header(%URI{scheme: "https", host: host, port: 443}), do: host
  defp host_header(%URI{scheme: "http", host: host, port: 80}), do: host
  defp host_header(%URI{host: host, port: port}), do: "#{host}:#{port}"

  defp request_target(%URI{path: path, query: nil}), do: nonempty_path(path)
  defp request_target(%URI{path: path, query: query}), do: "#{nonempty_path(path)}?#{query}"
  defp nonempty_path(path) when path in [nil, ""], do: "/"
  defp nonempty_path(path), do: path
end
