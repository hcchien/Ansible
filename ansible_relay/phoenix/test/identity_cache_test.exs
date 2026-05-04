defmodule AnsibleRelay.IdentityCacheTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleRelay.Repo)

    # Start the GenServer if not already started (creates ETS tables)
    case AnsibleRelay.IdentityCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "put and get a DID" do
    did = "did:key:z6MkTest#{System.unique_integer()}"
    nullifier = "nullifier_#{System.unique_integer()}"
    AnsibleRelay.IdentityCache.put(did, "abcdef0123456789", nullifier)
    assert {:ok, entry} = AnsibleRelay.IdentityCache.get(did)
    assert entry.public_key_hex == "abcdef0123456789"
    assert entry.nullifier == nullifier
  end

  test "verified? returns true for a fresh DID" do
    did = "did:key:z6MkVerify#{System.unique_integer()}"
    AnsibleRelay.IdentityCache.put(did, "pubkey", "null_#{System.unique_integer()}")
    assert AnsibleRelay.IdentityCache.verified?(did)
  end

  test "verified? returns false for unknown DID" do
    refute AnsibleRelay.IdentityCache.verified?("did:key:z6MkUnknown_#{System.unique_integer()}")
  end

  test "verified? returns false for expired DID" do
    did = "did:key:z6MkExpired#{System.unique_integer()}"
    past = DateTime.add(DateTime.utc_now(), -1, :second)
    AnsibleRelay.IdentityCache.put(did, "pubkey", "null_#{System.unique_integer()}", past)
    refute AnsibleRelay.IdentityCache.verified?(did)
  end

  test "remove deletes DID" do
    did = "did:key:z6MkRemove#{System.unique_integer()}"
    AnsibleRelay.IdentityCache.put(did, "pubkey", "null_#{System.unique_integer()}")
    AnsibleRelay.IdentityCache.remove(did)
    assert :not_found = AnsibleRelay.IdentityCache.get(did)
  end

  test "nullifier_exists? returns false before registration" do
    nullifier = "nullifier_fresh_#{System.unique_integer()}"
    refute AnsibleRelay.IdentityCache.nullifier_exists?(nullifier)
  end

  test "nullifier_exists? returns true after put" do
    did = "did:key:z6MkNull#{System.unique_integer()}"
    nullifier = "nullifier_used_#{System.unique_integer()}"
    AnsibleRelay.IdentityCache.put(did, "pubkey", nullifier)
    assert AnsibleRelay.IdentityCache.nullifier_exists?(nullifier)
  end

  test "remove also clears the nullifier index" do
    did = "did:key:z6MkNullRemove#{System.unique_integer()}"
    nullifier = "nullifier_remove_#{System.unique_integer()}"
    AnsibleRelay.IdentityCache.put(did, "pubkey", nullifier)
    AnsibleRelay.IdentityCache.remove(did)
    refute AnsibleRelay.IdentityCache.nullifier_exists?(nullifier)
  end

  test "public_key_hex returns the stored public key" do
    did = "did:key:z6MkPubKey#{System.unique_integer()}"
    AnsibleRelay.IdentityCache.put(did, "mypubkey123", "null_#{System.unique_integer()}")
    assert AnsibleRelay.IdentityCache.public_key_hex(did) == "mypubkey123"
  end

  test "public_key_hex returns nil for unknown DID" do
    assert AnsibleRelay.IdentityCache.public_key_hex("did:key:z6MkMissing_#{System.unique_integer()}") == nil
  end

  test "issue_challenge returns a nonce and expiry for a DID" do
    did = "did:key:z6MkChallenge#{System.unique_integer()}"

    assert {:ok, entry} = AnsibleRelay.IdentityCache.issue_challenge(did)
    assert is_binary(entry.challenge)
    assert byte_size(entry.challenge) > 20
    assert %DateTime{} = entry.expires_at
  end

  test "consume_challenge accepts a matching fresh challenge once" do
    did = "did:key:z6MkConsume#{System.unique_integer()}"
    {:ok, entry} = AnsibleRelay.IdentityCache.issue_challenge(did)

    assert :ok = AnsibleRelay.IdentityCache.consume_challenge(did, entry.challenge)
    assert {:error, :invalid_challenge} =
             AnsibleRelay.IdentityCache.consume_challenge(did, entry.challenge)
  end

  test "consume_challenge rejects mismatched challenge" do
    did = "did:key:z6MkMismatch#{System.unique_integer()}"
    {:ok, _entry} = AnsibleRelay.IdentityCache.issue_challenge(did)

    assert {:error, :invalid_challenge} =
             AnsibleRelay.IdentityCache.consume_challenge(did, "wrong-challenge")
  end

  test "consume_challenge rejects expired challenge" do
    did = "did:key:z6MkExpiredChallenge#{System.unique_integer()}"
    past = DateTime.add(DateTime.utc_now(), -1, :second)
    {:ok, entry} = AnsibleRelay.IdentityCache.issue_challenge(did, past)

    assert {:error, :expired_challenge} =
             AnsibleRelay.IdentityCache.consume_challenge(did, entry.challenge)
  end
end
