defmodule AnsibleRelay.AbuseDetectorTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.AbuseDetector

  setup do
    case AbuseDetector.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    previous = Application.get_env(:ansible_relay, :abuse_detector)

    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 2, refill_per_second: 0, suspension_ms: 500},
      peer: %{capacity: 1, refill_per_second: 0, suspension_ms: 500}
    })

    AbuseDetector.reset()

    on_exit(fn ->
      AbuseDetector.reset()

      if is_nil(previous) do
        Application.delete_env(:ansible_relay, :abuse_detector)
      else
        Application.put_env(:ansible_relay, :abuse_detector, previous)
      end
    end)

    :ok
  end

  test "check_did allows requests while tokens remain" do
    did = "did:key:z6MkAllowed#{System.unique_integer()}"

    assert :ok = AbuseDetector.check_did(did)
    assert :ok = AbuseDetector.check_did(did)
  end

  test "check_did rate limits and suspends after tokens are exhausted" do
    did = "did:key:z6MkLimited#{System.unique_integer()}"

    assert :ok = AbuseDetector.check_did(did)
    assert :ok = AbuseDetector.check_did(did)
    assert {:error, :rate_limited, detail} = AbuseDetector.check_did(did)

    assert detail.reason == "did_rate_limited"
    assert detail.subject_type == "did"
    assert detail.retry_after_ms > 0
    assert AbuseDetector.suspended?(:did, did)
  end

  test "reset clears suspension state" do
    did = "did:key:z6MkReset#{System.unique_integer()}"

    AbuseDetector.check_did(did)
    AbuseDetector.check_did(did)
    AbuseDetector.check_did(did)
    assert AbuseDetector.suspended?(:did, did)

    AbuseDetector.reset()
    refute AbuseDetector.suspended?(:did, did)
    assert :ok = AbuseDetector.check_did(did)
  end

  test "check_peer applies peer policy separately" do
    peer_id = "peer-#{System.unique_integer()}"

    assert :ok = AbuseDetector.check_peer(peer_id)
    assert {:error, :rate_limited, detail} = AbuseDetector.check_peer(peer_id)
    assert detail.reason == "peer_rate_limited"
  end
end
