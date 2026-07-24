defmodule AnsibleRelay.ForumHost.TrustedMembershipIssuer do
  @moduledoc "Operator-pinned public key resolver for hosted membership issuers."

  def resolve(issuer_did, key_id) when is_binary(issuer_did) and is_binary(key_id) do
    case Enum.find(entries(), &match_entry?(&1, issuer_did, key_id)) do
      %{} = entry -> decode_multibase_key(entry)
      nil -> resolve_system_issuer(issuer_did, key_id)
    end
  end

  def resolve(_, _), do: {:error, :issuer_not_trusted}

  def status_url_allowed?(url) when is_binary(url) do
    with %URI{scheme: "https", host: host, port: port} <- URI.parse(url) do
      Enum.any?(entries(), fn entry ->
        case URI.parse(get(entry, :status_origin) || "") do
          %URI{scheme: "https", host: ^host, port: ^port} -> true
          _ -> false
        end
      end) or trusted_system_issuer_host?(host, port)
    else
      _ -> false
    end
  end

  def status_url_allowed?(_), do: false

  defp entries, do: Application.get_env(:ansible_relay, :trusted_membership_issuers, [])
  defp system_entries, do: Application.get_env(:ansible_relay, :trusted_vc_issuers, [])

  defp match_entry?(entry, issuer, key),
    do: get(entry, :did) == issuer and get(entry, :key_id) == key

  defp decode_multibase_key(entry) do
    with "u" <> encoded <- get(entry, :public_key_multibase),
         {:ok, key} <- Base.url_decode64(encoded, padding: false),
         true <- byte_size(key) == 32 do
      {:ok, key}
    else
      _ -> {:error, :issuer_not_trusted}
    end
  end

  defp resolve_system_issuer(issuer_did, key_id) do
    with true <- key_id == issuer_did <> "#key-1",
         %{} = entry <- Enum.find(system_entries(), &(get(&1, :did) == issuer_did)),
         key_hex when is_binary(key_hex) <- get(entry, :public_key_hex),
         {:ok, key} <- Base.decode16(key_hex, case: :mixed),
         true <- byte_size(key) == 32 do
      {:ok, key}
    else
      _ -> {:error, :issuer_not_trusted}
    end
  end

  defp trusted_system_issuer_host?(host, port) do
    Enum.any?(system_entries(), fn entry ->
      case did_web_origin(get(entry, :did)) do
        %URI{host: ^host, port: ^port} -> true
        _ -> false
      end
    end)
  end

  defp did_web_origin("did:web:" <> encoded_host) do
    host =
      encoded_host
      |> String.split(":")
      |> hd()
      |> URI.decode()

    URI.parse("https://" <> host)
  end

  defp did_web_origin(_), do: nil

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
