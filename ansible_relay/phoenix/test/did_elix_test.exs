defmodule AnsibleRelay.DidElixTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.DidElix

  # Cross-language vectors generated from the Dart `deriveDidElix`
  # (ansible_core/store) — these MUST match byte-for-byte so an anchor minted
  # by the app self-certifies on the relay.
  test "derive matches the Dart vectors byte-for-byte" do
    assert DidElix.derive(String.duplicate("aa", 32), "alice.elix.cool") ==
             "did:elix:nxdvwwzy2n6zokf7lhepbvgdl4"

    assert DidElix.derive(
             "b97c30de767f084ce3080168ee293053ba33b235d7116a3263d29f1450936b71",
             "bob.elix.cool"
           ) ==
             "did:elix:w7paqjxbehs6ukzuj72t2uvzau"
  end

  test "matches?/3 self-certifies a canonical did:elix" do
    key = String.duplicate("aa", 32)
    did = DidElix.derive(key, "alice.elix.cool")
    assert DidElix.matches?(did, key, "alice.elix.cool")
    refute DidElix.matches?(did, key, "mallory.elix.cool")
    refute DidElix.matches?(did, String.duplicate("bb", 32), "alice.elix.cool")
    refute DidElix.matches?("did:elix:forged", key, "alice.elix.cool")
  end
end
