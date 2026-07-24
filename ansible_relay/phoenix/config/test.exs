import Config

config :ansible_relay, AnsibleRelay.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  database: System.get_env("POSTGRES_DB") || "ansible_relay_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :ansible_relay, :port, String.to_integer(System.get_env("RELAY_TEST_PORT") || "4002")

# Push wakes: capture sends in-process and shrink the debounce window so
# burst-coalescing tests stay fast.
config :ansible_relay, :push_sender, AnsibleRelay.Push.TestSender
config :ansible_relay, :push_wake_debounce_ms, 100
config :ansible_relay, :persist_did_accounts, false
config :ansible_relay, :allow_dev_zkp_proofs, true
# Most controller fixtures exercise historical Ed25519 verification. Dedicated
# policy tests override this to the production P-256-only setting.
config :ansible_relay, :identity_write_algorithms, ["ed25519", "p256-sha256"]

# The OpStore firehose settle guard keys off transaction xids, but the Ecto SQL
# sandbox wraps each statement in a savepoint (subtransaction), so an inserted
# row's xmin never matches the reader's snapshot the way it does across real
# committed transactions. Disable the guard for sandboxed tests; the raw-
# connection op_store_gap_test.exs exercises the real guarded SQL directly.
config :ansible_relay, :op_store_settle_guard, false

config :ansible_relay, :trusted_vc_issuers, [
  %{
    did: System.get_env("ISSUER_DID") || "did:web:issuer.elix.cool",
    public_key_hex:
      System.get_env("ISSUER_PUBLIC_KEY_HEX") ||
        "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  }
]
