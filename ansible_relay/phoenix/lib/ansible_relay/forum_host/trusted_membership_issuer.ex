defmodule AnsibleRelay.ForumHost.TrustedMembershipIssuer do
  @moduledoc "Operator-pinned public key resolver for hosted membership issuers."

  def resolve(issuer_did, key_id) when is_binary(issuer_did) and is_binary(key_id) do
    with %{} = entry <- Enum.find(entries(), &match_entry?(&1, issuer_did, key_id)),
         "u" <> encoded <- get(entry, :public_key_multibase),
         {:ok, key} <- Base.url_decode64(encoded, padding: false),
         true <- byte_size(key) == 32 do
      {:ok, key}
    else
      _ -> {:error, :issuer_not_trusted}
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
      end)
    else
      _ -> false
    end
  end

  def status_url_allowed?(_), do: false

  defp entries, do: Application.get_env(:ansible_relay, :trusted_membership_issuers, [])

  defp match_entry?(entry, issuer, key),
    do: get(entry, :did) == issuer and get(entry, :key_id) == key

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
