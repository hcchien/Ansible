#!/usr/bin/env bash
# Production readiness preflight for the Genesis stack.
# Fails loudly (exit 1) if any required secret/env is missing or placeholder-
# valued, or if the relay's pinned issuer public key does not match the private
# key in Secret Manager.
#
# Reads secret VALUES (to validate them) but never prints them.
# Requires: gcloud; python3 (stdlib json, for parsing service env);
#           openssl + xxd for the Ed25519 key-match check (self-tested against
#           an RFC 8032 vector; degrades to a documented manual step if absent).
#
# Usage: scripts/gcp/check_prod_readiness.sh --project <id> [--region asia-east1]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/gcp/common.sh
source "$SCRIPT_DIR/common.sh"

parse_common_flags "$@"
[ ${#REST_ARGS[@]} -eq 0 ] || die "unexpected argument(s): ${REST_ARGS[*]}"
require_project

FAILURES=0
WARNINGS=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() {
  printf 'FAIL  %s\n' "$*"
  FAILURES=$((FAILURES + 1))
}
note() {
  printf 'WARN  %s\n' "$*"
  WARNINGS=$((WARNINGS + 1))
}

lower() { tr '[:upper:]' '[:lower:]'; }

# --- secret validation ---------------------------------------------------------

read_secret() {
  gcloud secrets versions access latest --secret="$1" --project "$PROJECT_ID" 2>/dev/null
}

contains_dev_sentinel() {
  # Mirrors the issuer's boot-time sentinel list (cmd/server/main.go).
  case "$(printf '%s' "$1" | lower)" in
    *placeholder* | *changeme* | *dev-* | *example* | *test-pepper*) return 0 ;;
    *) return 1 ;;
  esac
}

is_hex_seed() {
  printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{64}$'
}

is_degenerate_seed() {
  # all one repeated character ("0000...", "aaaa...") — a hand-typed placeholder.
  [ -n "$1" ] && [ "$(printf '%s' "$1" | fold -w1 | sort -u | wc -l | tr -d ' ')" = "1" ]
}

# check_secret <name> <kind: hex-seed|token|db-url> [required|optional]
check_secret() {
  local name="$1" kind="$2" requirement="${3:-required}" value
  if ! value="$(read_secret "$name")" || [ -z "$value" ]; then
    if [ "$requirement" = "optional" ]; then
      note "secret $name missing/empty (optional — related feature stays disabled)"
    else
      fail "secret $name missing or empty (run scripts/gcp/provision.sh)"
    fi
    return
  fi
  if contains_dev_sentinel "$value"; then
    fail "secret $name contains a dev/placeholder sentinel value"
    return
  fi
  case "$kind" in
    hex-seed)
      if ! is_hex_seed "$value"; then
        fail "secret $name is not a 64-char hex Ed25519 seed"
        return
      fi
      if is_degenerate_seed "$value"; then
        fail "secret $name is a repeated-character placeholder seed"
        return
      fi
      ;;
    token)
      if [ "${#value}" -lt 32 ]; then
        fail "secret $name is shorter than 32 chars (weak/hand-typed?)"
        return
      fi
      ;;
    db-url)
      case "$value" in
        ecto://*localhost* | ecto://*127.0.0.1* | *localhost* | *127.0.0.1*)
          fail "secret $name points at localhost"
          return
          ;;
        ecto://*) ;;
        *)
          fail "secret $name is not an ecto:// connection URL"
          return
          ;;
      esac
      ;;
  esac
  pass "secret $name present and plausible (${#value} chars)"
}

log "checking Secret Manager secrets"
check_secret relay-database-url db-url
check_secret appview-database-url db-url optional
check_secret issuer-priv-key hex-seed
check_secret subject-commitment-pepper token
check_secret tw-provider-shared-secret token
check_secret relay-snapshot-signing-key hex-seed
check_secret issuer-admin-token token optional

# --- deployed service env checks -------------------------------------------------

SERVICE_JSON=""
fetch_service_json() {
  SERVICE_JSON="$(gcloud run services describe "$1" \
    --region "$REGION" --project "$PROJECT_ID" --format=json 2>/dev/null)" || SERVICE_JSON=""
}

service_env() { # <VAR> — from the last fetch_service_json
  printf '%s' "$SERVICE_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
env = data.get("spec", {}).get("template", {}).get("spec", {}) \
          .get("containers", [{}])[0].get("env") or []
print({e.get("name"): e.get("value", "") for e in env}.get(sys.argv[1], ""))
' "$1"
}

service_scale() { # prints "<minScale> <maxScale>" ("" when unset)
  printf '%s' "$SERVICE_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
ann = data.get("spec", {}).get("template", {}).get("metadata", {}).get("annotations", {})
print(ann.get("autoscaling.knative.dev/minScale", ""), ann.get("autoscaling.knative.dev/maxScale", ""))
'
}

require_https_env() { # <service> <VAR> <value>
  case "$3" in
    "") fail "$1: env $2 is unset" ;;
    *localhost* | *127.0.0.1*) fail "$1: env $2 contains localhost ($3)" ;;
    https://*) pass "$1: env $2 = $3" ;;
    *) fail "$1: env $2 is not https ($3)" ;;
  esac
}

command -v python3 >/dev/null || die "python3 is required to parse deployed service env"

log "checking deployed relay (ansible-relay)"
fetch_service_json ansible-relay
RELAY_PINNED_PUB=""
if [ -z "$SERVICE_JSON" ]; then
  note "ansible-relay not deployed yet — skipping relay env checks"
else
  require_https_env ansible-relay RELAY_ORIGIN "$(service_env RELAY_ORIGIN)"
  require_https_env ansible-relay FORUM_HOST_BASE_URL "$(service_env FORUM_HOST_BASE_URL)"
  require_https_env ansible-relay WEB_ALLOWED_ORIGINS "$(service_env WEB_ALLOWED_ORIGINS)"
  RELAY_PINNED_PUB="$(service_env ISSUER_PUBLIC_KEY_HEX)"
  if is_hex_seed "$RELAY_PINNED_PUB" && ! is_degenerate_seed "$RELAY_PINNED_PUB"; then
    pass "ansible-relay: ISSUER_PUBLIC_KEY_HEX is well-formed"
  else
    fail "ansible-relay: ISSUER_PUBLIC_KEY_HEX missing/malformed/placeholder"
    RELAY_PINNED_PUB=""
  fi
  ZKP_ENV="$(service_env ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS)"
  if [ -z "$ZKP_ENV" ]; then
    pass "ansible-relay: ZKP verification keys unset (path disabled, fail closed)"
  elif contains_dev_sentinel "$ZKP_ENV"; then
    fail "ansible-relay: ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS contains a placeholder (boot will refuse it)"
  else
    pass "ansible-relay: ZKP verification keys explicitly configured"
  fi
fi

log "checking deployed issuer (ansible-issuer)"
fetch_service_json ansible-issuer
if [ -z "$SERVICE_JSON" ]; then
  note "ansible-issuer not deployed yet — skipping issuer checks"
else
  read -r MIN_SCALE MAX_SCALE <<<"$(service_scale)"
  ISSUER_DB="$(service_env DATABASE_URL)"
  if [ "$MIN_SCALE" = "1" ] && [ "$MAX_SCALE" = "1" ]; then
    pass "ansible-issuer pinned to exactly 1 instance (min=max=1)"
  elif [ -n "$ISSUER_DB" ]; then
    note "ansible-issuer not pinned to 1 instance but DATABASE_URL is set (Postgres stores — allowed)"
  else
    fail "ansible-issuer must run min=max=1 while file-backed (found min='${MIN_SCALE}' max='${MAX_SCALE}', no DATABASE_URL)"
  fi
  if [ -n "$(service_env MOCK_MODE)" ]; then
    fail "ansible-issuer: MOCK_MODE is set — never in production"
  else
    pass "ansible-issuer: MOCK_MODE unset"
  fi
  if [ "$(service_env TW_PROVIDER_ADAPTER_MODE)" = "production" ]; then
    note "ansible-issuer: TW_PROVIDER_ADAPTER_MODE=production fails closed until the real adapter lands"
  fi
fi

log "checking deployed appview (ansible-appview)"
fetch_service_json ansible-appview
if [ -z "$SERVICE_JSON" ]; then
  note "ansible-appview not deployed (optional Component D) — skipping"
else
  read -r MIN_SCALE MAX_SCALE <<<"$(service_scale)"
  if [ "$MIN_SCALE" = "1" ] && [ "$MAX_SCALE" = "1" ]; then
    pass "ansible-appview pinned to 1 instance (single ingest poller)"
  elif [ -n "$(service_env REDIS_URL)" ]; then
    note "ansible-appview scaled out with REDIS_URL set — ensure a single ingest instance (scaling_operations.md)"
  else
    fail "ansible-appview must run min=max=1 without REDIS_URL (found min='${MIN_SCALE}' max='${MAX_SCALE}')"
  fi
fi

log "checking deployed frontend (ansible-web)"
fetch_service_json ansible-web
if [ -z "$SERVICE_JSON" ]; then
  note "ansible-web not deployed yet — skipping"
else
  require_https_env ansible-web RELAY_BASE_URL "$(service_env RELAY_BASE_URL)"
fi

# --- issuer keypair match ---------------------------------------------------------
# Derives the Ed25519 public key from the 32-byte seed in issuer-priv-key by
# wrapping the seed in a PKCS#8 DER envelope and asking openssl for the public
# half. Self-tested against RFC 8032 test vector 1 first: if the local
# openssl/xxd cannot reproduce the vector, the check degrades to a documented
# manual step instead of trusting broken tooling.

derive_ed25519_pub() { # <seed-hex> -> pubkey hex on stdout, or non-zero
  printf '302e020100300506032b657004220420%s' "$(printf '%s' "$1" | lower)" |
    xxd -r -p |
    openssl pkey -inform DER -pubout -outform DER 2>/dev/null |
    tail -c 32 | xxd -p -c 32
}

log "checking issuer keypair match (relay ISSUER_PUBLIC_KEY_HEX vs issuer-priv-key)"
DERIVATION_OK=false
if command -v openssl >/dev/null && command -v xxd >/dev/null; then
  RFC_SEED="9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  RFC_PUB="d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  if [ "$(derive_ed25519_pub "$RFC_SEED" || true)" = "$RFC_PUB" ]; then
    DERIVATION_OK=true
  fi
fi

if [ "$DERIVATION_OK" != true ]; then
  note "local openssl/xxd cannot derive Ed25519 public keys — verify manually:
      1. On a machine with OpenSSL >= 1.1.1 and xxd, run:
         gcloud secrets versions access latest --secret=issuer-priv-key --project $PROJECT_ID \\
           | { read -r SEED; printf '302e020100300506032b657004220420%s' \"\$SEED\"; } \\
           | xxd -r -p | openssl pkey -inform DER -pubout -outform DER | tail -c 32 | xxd -p -c 32
      2. Compare with ISSUER_PUBLIC_KEY_HEX on ansible-relay. They MUST match."
elif [ -z "$RELAY_PINNED_PUB" ]; then
  note "relay not deployed / key malformed — keypair match not verifiable yet"
else
  ISSUER_SEED="$(read_secret issuer-priv-key || true)"
  if [ -z "$ISSUER_SEED" ]; then
    fail "cannot read issuer-priv-key to verify the keypair"
  else
    DERIVED_PUB="$(derive_ed25519_pub "$ISSUER_SEED" || true)"
    if [ "$DERIVED_PUB" = "$(printf '%s' "$RELAY_PINNED_PUB" | lower)" ]; then
      pass "relay ISSUER_PUBLIC_KEY_HEX matches the public half of issuer-priv-key"
    else
      fail "relay ISSUER_PUBLIC_KEY_HEX does NOT match issuer-priv-key — VC verification will reject every credential"
    fi
  fi
fi

# --- summary ----------------------------------------------------------------------
echo
if [ "$FAILURES" -gt 0 ]; then
  die "$FAILURES check(s) FAILED, $WARNINGS warning(s). Not production ready."
fi
log "all checks passed ($WARNINGS warning(s))."
