import Config

config :ansible_relay, ecto_repos: [AnsibleRelay.Repo]

# Erlang clustering topologies. Empty = single node (default). runtime.exs builds
# a topology from env for multi-node (GKE) deployments; Cloud Run scales
# statelessly over shared PostgreSQL and does not require this.
config :libcluster, topologies: []

config :ansible_relay, AnsibleRelay.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 10

# 90 days
config :ansible_relay, :did_cache_ttl_seconds, 7_776_000
# 10 minutes
config :ansible_relay, :identity_challenge_ttl_seconds, 600
# Recovery re-anchor grace window (hijack resistance). 72h default — a
# recovery anchor is held `pending` for this long and any previously-enrolled
# key may veto-to-freeze before it promotes to active.
config :ansible_relay, :identity_recovery_grace_seconds, 259_200
config :ansible_relay, :port, 4000

# Phase 2.3 — op snapshot lifecycle.
# Snapshot signing key: a 32-byte Ed25519 seed in lowercase hex (64 chars).
# Unset here so dev/test derive a deterministic local key; production sets it
# from ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX (see runtime.exs).
config :ansible_relay, :snapshot_signing_key_hex, nil
# Op retention window in days. `:infinity` (default) NEVER prunes anything;
# set to an integer N to enable the guarded prune (snapshot-covered, non-
# tombstone ops older than N days). Tombstones/moderation rows are never pruned.
config :ansible_relay, :snapshot_retention_days, :infinity
config :ansible_relay, :allow_dev_identity_signatures, false
config :ansible_relay, :allow_dev_publication_signatures, false
config :ansible_relay, :allow_dev_zkp_proofs, false

config :ansible_relay, :zkp_verification_keys, [
  %{
    version: "passport_v1_groth16_bn254",
    hash: "sha256:dev-vk-hash-placeholder",
    status: :active
  },
  %{version: "passport_v1_dev", hash: "sha256:dev-passport-v1-placeholder", status: :active}
]

# SOSP abuse detector defaults. A DID posting more than 5 Ops/second is
# temporarily suspended from local relay ingestion.
config :ansible_relay, :abuse_detector, %{
  did: %{
    capacity: 5,
    refill_per_second: 5,
    suspension_ms: 60_000
  },
  peer: %{
    capacity: 20,
    refill_per_second: 20,
    suspension_ms: 60_000
  }
}

# Issuer Trust Registry for VP verification (layered identity Phase B).
# Each entry: %{
#   did: string,                # issuer did:web (never did:key — must be nameable)
#   public_key_hex: string,     # issuer assertion key
#   credential_types: [string]  # OPTIONAL — restrict which VC types this issuer
#                               # is trusted to issue; omit = any recognised type
# }
# A valid issuer signature is necessary but NOT sufficient: an issuer absent
# from this list (or not registered for the presented credential type) is
# rejected with `:untrusted_issuer`, distinct from a bad-signature
# `:invalid_vc_proof`. Dev/test fixtures live in their environment files;
# production issuers are required in runtime.exs so a release cannot silently
# trust a public test-vector key.
config :ansible_relay, :trusted_vc_issuers, []

import_config "#{config_env()}.exs"
