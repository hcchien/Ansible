defmodule AnsibleAppview.Ingest.SafeHttp do
  @moduledoc """
  SSRF/DoS-hardened outbound HTTP GET for ingest (relay delta + external
  outbox). Every outbound fetch in the AppView goes through here so the
  defenses are applied uniformly:

    * **No implicit redirects.** `:httpc` autoredirect is disabled; redirects
      are followed manually (bounded by `@max_redirects`) and every hop's URL
      is re-validated before it is fetched, so a `200` at a public host cannot
      be turned into a read of `169.254.169.254` via a `Location` header.

    * **Destination allow-scope.** The host of every URL (initial and each
      redirect hop) is resolved to its A/AAAA addresses and rejected if ANY
      resolved address is loopback, private (RFC-1918), link-local
      (including the cloud-metadata `169.254.169.254`), unique-local (IPv6
      `fc00::/7`), or otherwise non-global. Only `http`/`https` on the default
      or an explicit port are allowed.

    * **Body cap.** Responses larger than `@max_body_bytes` are refused
      (`{:error, :body_too_large}`) rather than buffered without bound.

  Dependency-free (OTP `:httpc` + `:inet`), matching the rest of ingest.
  """

  require Logger

  @max_redirects 3
  @max_body_bytes 5_000_000
  @timeout_ms 15_000

  @type headers :: [{charlist(), charlist()}]

  @doc """
  GET `url`, returning `{:ok, body_binary}` or `{:error, reason}`.

  `accept` sets the Accept header. All SSRF/redirect/body-size checks above are
  applied. Never raises for a network/validation failure — the caller treats
  `{:error, _}` as a tolerated miss.
  """
  @spec get(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def get(url, accept \\ "application/json") when is_binary(url) do
    do_get(url, accept, @max_redirects)
  end

  defp do_get(_url, _accept, redirects_left) when redirects_left < 0,
    do: {:error, :too_many_redirects}

  defp do_get(url, accept, redirects_left) do
    with :ok <- validate_url(url) do
      request = {String.to_charlist(url), [{~c"accept", String.to_charlist(accept)}]}

      # autoredirect: false — we follow (and re-validate) redirects ourselves.
      case :httpc.request(
             :get,
             request,
             [{:timeout, @timeout_ms}, {:autoredirect, false}],
             body_format: :binary
           ) do
        {:ok, {{_http, 200, _reason}, _headers, body}} ->
          if byte_size(body) > @max_body_bytes do
            {:error, :body_too_large}
          else
            {:ok, body}
          end

        {:ok, {{_http, status, _reason}, headers, _body}} when status in 300..399 ->
          case location(headers) do
            nil ->
              {:error, {:http_status, status}}

            loc ->
              next = resolve_redirect(url, loc)
              do_get(next, accept, redirects_left - 1)
          end

        {:ok, {{_http, status, _reason}, _headers, _body}} ->
          {:error, {:http_status, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp location(headers) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == "location", do: to_string(v)
    end)
  end

  # Redirects may be relative; resolve against the previous absolute URL.
  defp resolve_redirect(base, location) do
    base_uri = URI.parse(base)
    URI.merge(base_uri, location) |> URI.to_string()
  end

  @doc """
  Validate that `url` is an http/https URL whose host resolves only to
  globally-routable addresses. Public so the SSRF logic is unit-testable
  without a network round-trip.
  """
  @spec validate_url(String.t()) :: :ok | {:error, term()}
  def validate_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, {:blocked_scheme, uri.scheme}}

      is_nil(uri.host) or uri.host == "" ->
        {:error, :no_host}

      true ->
        validate_host(uri.host)
    end
  end

  defp validate_host(host) do
    case resolve_all(host) do
      {:ok, []} ->
        {:error, :unresolvable_host}

      {:ok, addrs} ->
        if Enum.all?(addrs, &global_address?/1) do
          :ok
        else
          {:error, {:blocked_ip, host}}
        end

      {:error, reason} ->
        {:error, {:resolve_failed, reason}}
    end
  end

  # Resolve a host (or literal IP) to every A/AAAA address it maps to. A literal
  # IP resolves to itself. All resolved addresses must pass the global check so a
  # multi-A record cannot smuggle in one private target.
  defp resolve_all(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, addr} ->
        {:ok, [addr]}

      {:error, _} ->
        v4 = lookup(charlist, :inet)
        v6 = lookup(charlist, :inet6)

        case v4 ++ v6 do
          [] -> {:error, :nxdomain}
          addrs -> {:ok, addrs}
        end
    end
  end

  defp lookup(charlist, family) do
    case :inet.getaddrs(charlist, family) do
      {:ok, addrs} -> addrs
      {:error, _} -> []
    end
  end

  @doc "True only for globally-routable unicast addresses (blocks SSRF targets)."
  @spec global_address?(:inet.ip_address()) :: boolean()
  # IPv4
  def global_address?({127, _, _, _}), do: false
  def global_address?({10, _, _, _}), do: false
  def global_address?({172, b, _, _}) when b >= 16 and b <= 31, do: false
  def global_address?({192, 168, _, _}), do: false
  def global_address?({169, 254, _, _}), do: false
  # 100.64.0.0/10 carrier-grade NAT
  def global_address?({100, b, _, _}) when b >= 64 and b <= 127, do: false
  # 0.0.0.0/8 "this host"
  def global_address?({0, _, _, _}), do: false
  # 192.0.0.0/24, 192.0.2.0/24 (TEST-NET-1), 198.18/15, 198.51.100/24, 203.0.113/24
  def global_address?({192, 0, 0, _}), do: false
  def global_address?({192, 0, 2, _}), do: false
  def global_address?({198, 18, _, _}), do: false
  def global_address?({198, 19, _, _}), do: false
  def global_address?({198, 51, 100, _}), do: false
  def global_address?({203, 0, 113, _}), do: false
  # 224.0.0.0/4 multicast, 240.0.0.0/4 reserved
  def global_address?({a, _, _, _}) when a >= 224, do: false
  def global_address?({_, _, _, _}), do: true

  # IPv6
  def global_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  def global_address?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  # ::ffff:0:0/96 IPv4-mapped — validate the embedded v4.
  def global_address?({0, 0, 0, 0, 0, 0xFFFF, ab, cd}),
    do: global_address?({div(ab, 256), rem(ab, 256), div(cd, 256), rem(cd, 256)})

  # fe80::/10 link-local
  def global_address?({a, _, _, _, _, _, _, _}) when a >= 0xFE80 and a <= 0xFEBF, do: false
  # fc00::/7 unique-local
  def global_address?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: false
  def global_address?({_, _, _, _, _, _, _, _}), do: true
  def global_address?(_), do: false
end
