import Config

# Issuer identity
config :ansible_issuer,
  issuer_did: System.get_env("ISSUER_DID") || "did:web:issuer.trisaura.io",
  issuer_service_url: System.get_env("ISSUER_SERVICE_URL") || "https://issuer.trisaura.io"

# Ed25519 signing keypair (hex-encoded 32-byte keys).
# Dev values: RFC 8032 test vector 1 — NEVER use in production.
# To generate a real keypair: mix run scripts/gen_issuer_key.exs
config :ansible_issuer,
  issuer_private_key_hex:
    System.get_env("ISSUER_PRIVATE_KEY_HEX") ||
      "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae3d55",
  issuer_public_key_hex:
    System.get_env("ISSUER_PUBLIC_KEY_HEX") ||
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

# VC TTL: 90 days
config :ansible_issuer, :vc_ttl_days, 90

# OTP TTL: 5 minutes
config :ansible_issuer, :otp_ttl_seconds, 300

# mock_mode: true  → return OTP directly in /request response (dev / CI only)
# mock_mode: false → send OTP via email (requires email adapter in P2)
config :ansible_issuer, :mock_mode, true

config :ansible_issuer, :port, 4002

import_config "#{config_env()}.exs"
