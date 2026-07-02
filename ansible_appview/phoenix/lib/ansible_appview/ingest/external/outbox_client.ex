defmodule AnsibleAppview.Ingest.External.OutboxClient do
  @moduledoc """
  Fetches a remote ActivityPub actor's public outbox over HTTP (OTP `:httpc`,
  same dependency-free approach as `Ingest.RelayClient`).

  Behaviour-based so tests inject a stub client and never hit the network.

  An AP outbox is an `OrderedCollection`; the first page is usually behind a
  `first` link (an `OrderedCollectionPage` with `orderedItems`). This client
  resolves at most one page deep and returns the raw activity/object maps for the
  normalizer to interpret. It returns `{:error, reason}` for any non-200 / decode
  failure; the caller (`ExternalIngest`) must treat that as a tolerated miss, not
  a crash.
  """

  @callback fetch_outbox(actor_uri :: String.t()) :: {:ok, [map()]} | {:error, term()}

  @doc "Resolve the configured client (default: this module's real :httpc impl)."
  def impl,
    do: Application.get_env(:ansible_appview, :external_outbox_client, __MODULE__)

  @doc "Fetch and flatten a remote actor's public outbox items."
  @spec fetch_outbox(String.t()) :: {:ok, [map()]} | {:error, term()}
  def fetch_outbox(actor_uri) when is_binary(actor_uri) do
    with {:ok, actor} <- get_json(actor_uri),
         {:ok, outbox_url} <- outbox_url(actor),
         {:ok, outbox} <- get_json(outbox_url) do
      resolve_items(outbox)
    end
  end

  defp outbox_url(%{"outbox" => url}) when is_binary(url) and url != "", do: {:ok, url}
  defp outbox_url(_), do: {:error, :no_outbox}

  # An OrderedCollection either carries items inline or points at a first page.
  defp resolve_items(%{"orderedItems" => items}) when is_list(items), do: {:ok, items}

  defp resolve_items(%{"first" => first}) when is_binary(first) do
    case get_json(first) do
      {:ok, %{"orderedItems" => items}} when is_list(items) -> {:ok, items}
      {:ok, _} -> {:ok, []}
      error -> error
    end
  end

  defp resolve_items(%{"first" => %{"orderedItems" => items}}) when is_list(items),
    do: {:ok, items}

  defp resolve_items(_), do: {:ok, []}

  defp get_json(url) do
    # SSRF/DoS-hardened fetch: no implicit redirects, private/loopback/link-local
    # destinations blocked at every hop, response body size capped.
    case AnsibleAppview.Ingest.SafeHttp.get(url, "application/activity+json, application/json") do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{} = map} -> {:ok, map}
          {:ok, _} -> {:error, :unexpected_body}
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
