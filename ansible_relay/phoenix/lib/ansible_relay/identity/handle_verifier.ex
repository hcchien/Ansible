defmodule AnsibleRelay.Identity.HandleVerifier do
  @moduledoc """
  DNS handle verification (architecture plan Phase 4.3): proves a
  custom-domain handle is controlled by the DID that claims it, using the
  atproto-compatible conventions so existing tooling and the future
  `did:plc` bridge interoperate:

    1. DNS TXT at `_atproto.<handle>` containing `did=<did>`
    2. Fallback: `https://<handle>/.well-known/atproto-did` whose body is
       the DID

  Either proof passing verifies the handle. Both resolvers are injectable
  for tests; production uses OTP's `:inet_res` (DNS) and `:httpc` (HTTPS —
  same no-new-dependency choice as the federated resolver).

  Relay-issued `*.elix.cool` handles don't need this (the relay is the
  authority for its own suffix); this is the path for bring-your-own-domain
  handles.
  """

  @type resolver_result :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Verifies that [handle] (a bare domain, e.g. `alice.example.com`) is
  controlled by [did]. Returns `{:ok, :dns | :well_known}` naming the proof
  that matched, or `{:error, :invalid_handle | :not_verified}`.
  """
  def verify(handle, did, opts \\ []) do
    dns = Keyword.get(opts, :dns_txt_resolver, &dns_txt/1)
    http = Keyword.get(opts, :well_known_resolver, &well_known/1)

    with :ok <- validate_handle(handle) do
      cond do
        dns_proof?(dns, handle, did) -> {:ok, :dns}
        well_known_proof?(http, handle, did) -> {:ok, :well_known}
        true -> {:error, :not_verified}
      end
    end
  end

  # Bare hostname: letters/digits/hyphens dot-separated, at least one dot,
  # no scheme/path/port — rejects URL smuggling into the resolvers.
  defp validate_handle(handle) when is_binary(handle) do
    if Regex.match?(~r/\A[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?)+\z/i, handle) do
      :ok
    else
      {:error, :invalid_handle}
    end
  end

  defp validate_handle(_handle), do: {:error, :invalid_handle}

  defp dns_proof?(resolver, handle, did) do
    case resolver.("_atproto.#{handle}") do
      {:ok, records} ->
        expected = "did=#{did}"
        Enum.any?(records, fn record -> String.trim(record) == expected end)

      {:error, _reason} ->
        false
    end
  end

  defp well_known_proof?(resolver, handle, did) do
    case resolver.(handle) do
      {:ok, [body | _]} -> String.trim(body) == did
      _ -> false
    end
  end

  # --- Production resolvers ---

  defp dns_txt(name) do
    case :inet_res.lookup(String.to_charlist(name), :in, :txt) do
      [] ->
        {:error, :no_records}

      records when is_list(records) ->
        {:ok,
         Enum.map(records, fn parts ->
           parts |> Enum.map(&to_string/1) |> Enum.join("")
         end)}
    end
  rescue
    _ -> {:error, :dns_failure}
  end

  defp well_known(handle) do
    url = ~c"https://#{handle}/.well-known/atproto-did"

    case :httpc.request(
           :get,
           {url, []},
           [timeout: 5_000, connect_timeout: 3_000],
           body_format: :binary
         ) do
      {:ok, {{_http, 200, _status}, _headers, body}} when byte_size(body) <= 1024 ->
        {:ok, [body]}

      _ ->
        {:error, :unreachable}
    end
  end
end
