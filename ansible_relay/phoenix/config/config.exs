import Config

config :ansible_relay, ecto_repos: [AnsibleRelay.Repo]

config :ansible_relay, AnsibleRelay.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 10

# 90 days
config :ansible_relay, :did_cache_ttl_seconds, 7_776_000
# 10 minutes
config :ansible_relay, :identity_challenge_ttl_seconds, 600
config :ansible_relay, :port, 4000
config :ansible_relay, :allow_dev_identity_signatures, false

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

# Trusted VC issuers for VP verification.
# Each entry: %{did: string, public_key_hex: string}
# Dev value: RFC 8032 test vector 1 public key — matches ansible_issuer dev config.
# Production: set ISSUER_DID and ISSUER_PUBLIC_KEY_HEX env vars.
config :ansible_relay, :trusted_vc_issuers, [
  %{
    did: System.get_env("ISSUER_DID") || "did:web:issuer.trisaura.io",
    public_key_hex:
      System.get_env("ISSUER_PUBLIC_KEY_HEX") ||
        "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  }
]

import_config "#{config_env()}.exs"
