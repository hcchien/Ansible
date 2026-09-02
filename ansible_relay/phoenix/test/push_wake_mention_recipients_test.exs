defmodule AnsibleRelay.Push.WakeMentionRecipientsTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.Push.WakeScheduler

  test "mention recipients are public DIDs, unique, not self, and capped" do
    author = "did:plc:author"

    recipients =
      WakeScheduler.mention_recipients(
        %{
          "mentionDids" => [
            "did:plc:alice",
            "did:plc:alice",
            author,
            "not-a-did",
            42
            | Enum.map(0..12, &"did:plc:user-#{&1}")
          ]
        },
        author
      )

    assert length(recipients) == 10
    assert hd(recipients) == "did:plc:alice"
    refute author in recipients
    refute "not-a-did" in recipients
  end

  test "missing or scalar mention payloads are safe" do
    assert WakeScheduler.mention_recipients(%{}, "did:plc:author") == []

    assert WakeScheduler.mention_recipients(
             %{"mentionDids" => "did:plc:alice"},
             "did:plc:author"
           ) == []
  end
end
