defmodule AnsibleAppview.Ingest.RelayClient do
  @moduledoc "Fetches the relay op delta over HTTP (OTP :httpc, no extra deps)."

  @spec fetch_delta(String.t(), integer(), pos_integer()) ::
          {:ok, %{ops: [map()], next_cursor: integer(), has_more: boolean()}}
          | {:error, term()}
  def fetch_delta(base_url, cursor, limit \\ 500) do
    url =
      "#{String.trim_trailing(base_url, "/")}/api/v1/ops/delta?cursor=#{cursor}&limit=#{limit}"

    # SSRF/DoS-hardened fetch: no implicit redirects, private/loopback/link-local
    # destinations blocked at every hop, response body size capped.
    case AnsibleAppview.Ingest.SafeHttp.get(url, "application/json") do
      {:ok, body} -> decode(body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, %{"ops" => ops} = map} when is_list(ops) ->
        {:ok,
         %{
           ops: ops,
           next_cursor: map["next_cursor"] || 0,
           has_more: map["has_more"] || false
         }}

      {:ok, _} ->
        {:error, :unexpected_body}

      error ->
        error
    end
  end
end
