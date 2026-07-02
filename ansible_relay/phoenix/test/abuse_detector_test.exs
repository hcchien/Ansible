defmodule AnsibleRelay.AbuseDetectorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

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

  test "sweep_now drops idle (fully-refilled, not-suspended) buckets" do
    # A fast-refilling policy so a spent token is back to full almost immediately.
    Application.put_env(:ansible_relay, :abuse_detector, %{
      did: %{capacity: 5, refill_per_second: 1_000_000, suspension_ms: 500},
      peer: %{capacity: 1, refill_per_second: 0, suspension_ms: 500}
    })

    AbuseDetector.reset()

    idle_did = "did:key:z6MkIdle#{System.unique_integer()}"
    suspended_peer = "peer-suspended-#{System.unique_integer()}"

    # Touch an idle DID bucket (refills to full instantly), and suspend a peer.
    assert :ok = AbuseDetector.check_did(idle_did)
    assert :ok = AbuseDetector.check_peer(suspended_peer)
    assert {:error, :rate_limited, _} = AbuseDetector.check_peer(suspended_peer)
    assert AbuseDetector.suspended?(:peer, suspended_peer)

    Process.sleep(5)
    :ok = AbuseDetector.sweep_now()

    # Idle bucket is gone (a fresh lookup behaves like a new bucket)...
    refute :ets.member(:ansible_relay_abuse_detector, {:did, idle_did})
    # ...but the still-suspended peer bucket is retained.
    assert AbuseDetector.suspended?(:peer, suspended_peer)
  end

  test "rate-limit logs separate raw DID and IP metadata behind hashes" do
    did = "did:plc:raw-log-test"
    ip = "203.0.113.55"

    log =
      capture_log(fn ->
        AbuseDetector.check_did(did)
        AbuseDetector.check_did(did)
        AbuseDetector.check_did(did)
        AbuseDetector.check_peer("web_session_challenge:#{ip}")
        AbuseDetector.check_peer("web_session_challenge:#{ip}")
      end)

    assert log =~ "subject_type=did"
    assert log =~ "subject_type=peer"
    assert log =~ "subject_hash="
    refute log =~ did
    refute log =~ ip
  end
end
