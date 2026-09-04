defmodule AnsibleRelay.Push.ApnsSenderTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Push.ApnsSender

  @device_token String.duplicate("a", 64)
  @config_keys [:apns, :apns_token_provider, :apns_requester]

  setup do
    previous = Map.new(@config_keys, &{&1, Application.get_env(:ansible_relay, &1)})

    Application.put_env(:ansible_relay, :apns,
      key_id: "TESTKEY01",
      team_id: "TESTTEAM01",
      key_p8: "unused-by-injected-token-provider",
      topic: "com.reviz.elix",
      environment: "production"
    )

    Application.put_env(:ansible_relay, :apns_token_provider, fn -> {:ok, "provider-jwt"} end)
    ApnsSender.reset_provider_token_cache()

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:ansible_relay, key)
        {key, value} -> Application.put_env(:ansible_relay, key, value)
      end)

      ApnsSender.reset_provider_token_cache()
    end)

    :ok
  end

  test "sends the exact content-free background wake to production APNs" do
    test_pid = self()

    Application.put_env(:ansible_relay, :apns_requester, fn url, headers, body ->
      send(test_pid, {:request, url, headers, body})
      :ok
    end)

    assert :ok = ApnsSender.send_wake(@device_token, "apns", %{"hint" => "sync"})

    assert_receive {:request, url, headers, body}
    assert url == "https://api.push.apple.com/3/device/#{@device_token}"
    assert {"authorization", "bearer provider-jwt"} in headers
    assert {"apns-topic", "com.reviz.elix"} in headers
    assert {"apns-push-type", "background"} in headers
    assert {"apns-priority", "5"} in headers

    assert Jason.decode!(body) == %{
             "aps" => %{"content-available" => 1},
             "hint" => "sync"
           }
  end

  test "uses the sandbox endpoint only when configured" do
    Application.put_env(:ansible_relay, :apns,
      key_id: "TESTKEY01",
      team_id: "TESTTEAM01",
      key_p8: "unused-by-injected-token-provider",
      topic: "com.reviz.elix",
      environment: "sandbox"
    )

    test_pid = self()

    Application.put_env(:ansible_relay, :apns_requester, fn url, _headers, _body ->
      send(test_pid, {:url, url})
      :ok
    end)

    assert :ok = ApnsSender.send_wake(@device_token, "apns", %{"hint" => "sync"})
    assert_receive {:url, "https://api.sandbox.push.apple.com/3/device/" <> @device_token}
  end

  test "retries transient HTTP/2 pool startup failures" do
    test_pid = self()

    Application.put_env(:ansible_relay, :apns_requester, fn _url, _headers, _body ->
      attempt = Process.get(:apns_request_attempt, 0) + 1
      Process.put(:apns_request_attempt, attempt)
      send(test_pid, {:attempt, attempt})

      if attempt < 3 do
        {:error, {:apns_transport, Finch.Error.exception(:pool_not_available)}}
      else
        :ok
      end
    end)

    assert :ok = ApnsSender.send_wake(@device_token, "apns", %{"hint" => "sync"})
    assert_receive {:attempt, 1}
    assert_receive {:attempt, 2}
    assert_receive {:attempt, 3}
  end

  test "rejects invalid tokens, unsupported platforms, and payload expansion" do
    assert {:error, :invalid_device_token} =
             ApnsSender.send_wake("not-a-token", "apns", %{"hint" => "sync"})

    assert {:error, :unsupported_platform} =
             ApnsSender.send_wake(@device_token, "fcm", %{"hint" => "sync"})

    assert {:error, :non_content_free_payload} =
             ApnsSender.send_wake(@device_token, "apns", %{
               "hint" => "sync",
               "mention" => "private content must not be pushed"
             })
  end

  test "generates and reuses an ES256 provider token" do
    Application.delete_env(:ansible_relay, :apns_token_provider)
    key = :public_key.generate_key({:namedCurve, :secp256r1})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, key)])

    Application.put_env(:ansible_relay, :apns,
      key_id: "TESTKEY01",
      team_id: "TESTTEAM01",
      key_p8: pem,
      topic: "com.reviz.elix",
      environment: "production"
    )

    test_pid = self()

    Application.put_env(:ansible_relay, :apns_requester, fn _url, headers, _body ->
      send(test_pid, {:authorization, List.keyfind(headers, "authorization", 0)})
      :ok
    end)

    assert :ok = ApnsSender.send_wake(@device_token, "apns", %{"hint" => "sync"})
    assert_receive {:authorization, {"authorization", "bearer " <> first_token}}
    assert length(String.split(first_token, ".")) == 3

    assert :ok = ApnsSender.send_wake(@device_token, "apns", %{"hint" => "sync"})
    assert_receive {:authorization, {"authorization", "bearer " <> second_token}}
    assert second_token == first_token
  end

  test "returns a closed error when APNs configuration is incomplete" do
    Application.delete_env(:ansible_relay, :apns)

    assert {:error, :apns_not_configured} =
             ApnsSender.send_wake(@device_token, "apns", %{"hint" => "sync"})
  end
end
