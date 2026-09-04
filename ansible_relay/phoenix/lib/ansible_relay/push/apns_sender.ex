defmodule AnsibleRelay.Push.ApnsSender do
  @moduledoc """
  HTTP/2 APNs transport for content-free sync wakes.

  This adapter deliberately rejects any payload other than the scheduler's
  exact `%{"hint" => "sync"}` marker. APNs receives only the required silent
  `aps.content-available` field plus that marker; mention content, actor data,
  and notification read state never cross the push boundary.
  """

  @behaviour AnsibleRelay.Push.PushSender

  @cache_key {__MODULE__, :provider_token}
  @provider_token_ttl_seconds 50 * 60
  @request_timeout_ms 10_000
  @impl true
  def send_wake(device_token, "apns", %{"hint" => "sync"} = payload)
      when is_binary(device_token) and map_size(payload) == 1 do
    with :ok <- validate_device_token(device_token),
         {:ok, provider_token} <- provider_token(),
         {:ok, config} <- config() do
      body = Jason.encode!(%{"aps" => %{"content-available" => 1}, "hint" => "sync"})

      headers = [
        {"authorization", "bearer #{provider_token}"},
        {"apns-topic", config.topic},
        {"apns-push-type", "background"},
        {"apns-priority", "5"},
        {"content-type", "application/json"}
      ]

      requester().(endpoint(config.environment, device_token), headers, body)
    end
  end

  def send_wake(_device_token, "apns", _payload), do: {:error, :non_content_free_payload}
  def send_wake(_device_token, _platform, _payload), do: {:error, :unsupported_platform}

  @doc false
  def reset_provider_token_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  defp provider_token do
    case Application.get_env(:ansible_relay, :apns_token_provider) do
      provider when is_function(provider, 0) -> provider.()
      _ -> cached_provider_token()
    end
  end

  defp cached_provider_token do
    now = System.system_time(:second)

    case :persistent_term.get(@cache_key, nil) do
      {token, issued_at}
      when is_binary(token) and now - issued_at < @provider_token_ttl_seconds ->
        {:ok, token}

      _ ->
        generate_and_cache_provider_token(now)
    end
  end

  defp generate_and_cache_provider_token(issued_at) do
    with {:ok, config} <- config() do
      try do
        jwk = JOSE.JWK.from_pem(config.key_p8)
        claims = %{"iss" => config.team_id, "iat" => issued_at}
        protected = %{"alg" => "ES256", "kid" => config.key_id}
        {_jws, token} = JOSE.JWT.sign(jwk, protected, claims) |> JOSE.JWS.compact()
        :persistent_term.put(@cache_key, {token, issued_at})
        {:ok, token}
      rescue
        _ -> {:error, :invalid_apns_private_key}
      end
    end
  end

  defp requester do
    Application.get_env(:ansible_relay, :apns_requester, &request/3)
  end

  defp request(url, headers, body) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, AnsibleRelay.Finch, receive_timeout: @request_timeout_ms) do
      {:ok, %Finch.Response{status: 200}} ->
        :ok

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        {:error, {:apns_rejected, status, response_reason(response_body)}}

      {:error, reason} ->
        {:error, {:apns_transport, reason}}
    end
  end

  defp response_reason(body) do
    case Jason.decode(body) do
      {:ok, %{"reason" => reason}} when is_binary(reason) -> reason
      _ -> "unknown"
    end
  end

  defp validate_device_token(token) do
    if Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, token),
      do: :ok,
      else: {:error, :invalid_device_token}
  end

  defp config do
    case Application.get_env(:ansible_relay, :apns) do
      values when is_list(values) ->
        required = [:key_id, :team_id, :key_p8, :topic, :environment]

        if Enum.all?(required, &(is_binary(values[&1]) and values[&1] != "")) do
          {:ok, Map.new(values)}
        else
          {:error, :apns_not_configured}
        end

      _ ->
        {:error, :apns_not_configured}
    end
  end

  defp endpoint("sandbox", token), do: "https://api.sandbox.push.apple.com/3/device/#{token}"
  defp endpoint("production", token), do: "https://api.push.apple.com/3/device/#{token}"
end
