defmodule AnsibleRelay.ForumHost.ReportRateLimiterTest do
  @moduledoc "Report limiter behavior plus the periodic idle-bucket sweep."

  use ExUnit.Case, async: false

  alias AnsibleRelay.ForumHost.ReportRateLimiter

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleRelay.Repo, {:shared, self()})

    for mod <- [AnsibleRelay.DidAccountCache, ReportRateLimiter] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    original = Application.get_env(:ansible_relay, :forum_host_report_limits)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:ansible_relay, :forum_host_report_limits)
      else
        Application.put_env(:ansible_relay, :forum_host_report_limits, original)
      end

      ReportRateLimiter.reset()
    end)

    ReportRateLimiter.reset()
    :ok
  end

  test "check_reporter allows within capacity then rate limits" do
    # Basic tier: capacity 3, no refill within the window.
    Application.put_env(:ansible_relay, :forum_host_report_limits, %{
      "basic" => %{capacity: 2, refill_per_second: 0, suspension_ms: 60_000}
    })

    did = "did:test:reporter#{System.unique_integer([:positive])}"

    assert :ok = ReportRateLimiter.check_reporter(did)
    assert :ok = ReportRateLimiter.check_reporter(did)
    assert {:error, :rate_limited, detail} = ReportRateLimiter.check_reporter(did)
    assert detail.reason == "report_rate_limited"
  end

  test "sweep_now drops an idle (fully-refilled) bucket" do
    # Fast refill so a single spent token is back to full within the sleep.
    Application.put_env(:ansible_relay, :forum_host_report_limits, %{
      "basic" => %{capacity: 3, refill_per_second: 1_000, suspension_ms: 60_000}
    })

    idle = "did:test:idle#{System.unique_integer([:positive])}"

    assert :ok = ReportRateLimiter.check_reporter(idle)
    assert :ets.member(:ansible_relay_forum_host_report_limiter, {:report, idle})

    # Let the one spent token refill (1000/s → full within a few ms).
    Process.sleep(20)
    :ok = ReportRateLimiter.sweep_now()

    refute :ets.member(:ansible_relay_forum_host_report_limiter, {:report, idle})
  end

  test "sweep_now keeps a still-suspended bucket" do
    # No refill so the bucket drains and stays suspended for the window.
    Application.put_env(:ansible_relay, :forum_host_report_limits, %{
      "basic" => %{capacity: 2, refill_per_second: 0, suspension_ms: 60_000}
    })

    suspended = "did:test:suspended#{System.unique_integer([:positive])}"

    Enum.each(1..2, fn _ -> ReportRateLimiter.check_reporter(suspended) end)
    assert {:error, :rate_limited, _} = ReportRateLimiter.check_reporter(suspended)

    :ok = ReportRateLimiter.sweep_now()

    assert :ets.member(:ansible_relay_forum_host_report_limiter, {:report, suspended})
  end
end
