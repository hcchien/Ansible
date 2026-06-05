defmodule AnsibleAppview.Ingest.RelayClient do
  @moduledoc "Fetches the relay op delta over HTTP (OTP :httpc, no extra deps)."

  @spec fetch_delta(String.t(), integer(), pos_integer()) ::
          {:ok, %{ops: [map()], next_cursor: integer(), has_more: boolean()}}
          | {:error, term()}
  def fetch_delta(base_url, cursor, limit \\ 500) do
    url =
      "#{String.trim_trailing(base_url, "/")}/api/v1/ops/delta?cursor=#{cursor}&limit=#{limit}"

    request = {String.to_charlist(url), [{~c"accept", ~c"application/json"}]}

    case :httpc.request(:get, request, [{:timeout, 15_000}], body_format: :binary) do
      {:ok, {{_http, 200, _reason}, _headers, body}} ->
        decode(body)

      {:ok, {{_http, status, _reason}, _headers, _body}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
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
