# shellcheck shell=bash
# Shared helpers for scripts/gcp/*. Sourced by provision.sh / deploy.sh /
# check_prod_readiness.sh — not executable on its own.
#
# Flags/env understood by every script:
#   --project <id>   (or env PROJECT_ID)
#   --region <name>  (or env REGION; default asia-east1)

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-asia-east1}"

# Resource names shared with docs/deployment/cloud_run_deploy.md. Override via
# env only if your deployment deliberately diverges from the runbook.
REPO="${REPO:-ansible}"
SQL_INSTANCE="${SQL_INSTANCE:-ansible-relay-db}"
VPC_CONNECTOR="${VPC_CONNECTOR:-ansible-conn}"
NETWORK="${NETWORK:-default}"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# Parses --project/--region out of "$@"; everything else lands in REST_ARGS.
# Usage: parse_common_flags "$@"; set -- "${REST_ARGS[@]}"
parse_common_flags() {
  REST_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) PROJECT_ID="${2:?--project needs a value}"; shift 2 ;;
      --project=*) PROJECT_ID="${1#*=}"; shift ;;
      --region) REGION="${2:?--region needs a value}"; shift 2 ;;
      --region=*) REGION="${1#*=}"; shift ;;
      *) REST_ARGS+=("$1"); shift ;;
    esac
  done
}

require_project() {
  [ -n "$PROJECT_ID" ] || die "set --project <id> or export PROJECT_ID"
  command -v gcloud >/dev/null || die "gcloud CLI not found on PATH"
}

# require_env NAME [NAME...] — every listed env var must be non-empty.
require_env() {
  local name missing=()
  for name in "$@"; do
    [ -n "${!name:-}" ] || missing+=("$name")
  done
  [ ${#missing[@]} -eq 0 ] || die "missing required env var(s): ${missing[*]}"
}

secret_exists() {
  gcloud secrets describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1
}

runtime_service_account() {
  local project_number
  project_number="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
  printf '%s-compute@developer.gserviceaccount.com' "$project_number"
}
