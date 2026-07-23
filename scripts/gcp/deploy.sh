#!/usr/bin/env bash
# Build + migrate + deploy one Genesis service to Cloud Run.
# Companion to docs/deployment/cloud_run_deploy.md (which explains every flag).
#
# Usage:
#   scripts/gcp/deploy.sh --project <id> [--region asia-east1] [--tag <sha>] <service>
#   service: relay | appview | issuer | verifier | frontend
#
# Required env per service (values, not secrets — secrets come from Secret
# Manager; see provision.sh):
#   relay:    RELAY_HOST WEB_HOST ISSUER_HOST ISSUER_PUBLIC_KEY_HEX
#             WEBAUTHN_RP_ID WEBAUTHN_ORIGIN
#             [UNIVERSAL_LINK_IOS_APP_IDS APP_LINK_ANDROID_PACKAGE
#              APP_LINK_ANDROID_SHA256_CERTS ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS]
#   appview:  RELAY_HOST
#   issuer:   ISSUER_HOST TW_PROVIDER_AUTH_URL [TW_PROVIDER_AUDIENCE
#              PASSPORT_VERIFIER_URL]
#   verifier: no additional variables
#   frontend: RELAY_HOST [APPVIEW_HOST UNIVERSAL_LINK_IOS_APP_IDS
#              APP_LINK_ANDROID_PACKAGE APP_LINK_ANDROID_SHA256_CERTS]
#
# Deploy order for a fresh stack: relay -> issuer -> appview -> frontend
# (docs/deployment/gcp_production_checklist.md).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/gcp/common.sh
source "$SCRIPT_DIR/common.sh"

TAG="${TAG:-}"
parse_common_flags "$@"
set -- "${REST_ARGS[@]+"${REST_ARGS[@]}"}"

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="${2:?--tag needs a value}"; shift 2 ;;
    --tag=*) TAG="${1#*=}"; shift ;;
    relay | appview | issuer | verifier | frontend) SERVICE="$1"; shift ;;
    *) die "unknown argument: $1 (expected relay|appview|issuer|verifier|frontend)" ;;
  esac
done

[ -n "${SERVICE:-}" ] || die "usage: deploy.sh --project <id> [--region <r>] [--tag <sha>] <relay|appview|issuer|verifier|frontend>"
require_project
[ -n "$TAG" ] || TAG="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

AR="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}"

# --- Per-service build config -------------------------------------------------
case "$SERVICE" in
  relay)
    CLOUDBUILD="ansible_relay/phoenix/cloudbuild.yaml"
    IMAGE="${AR}/ansible-relay:${TAG}"
    ;;
  appview)
    CLOUDBUILD="ansible_appview/phoenix/cloudbuild.yaml"
    IMAGE="${AR}/ansible-appview:${TAG}"
    ;;
  issuer)
    CLOUDBUILD="ansible_issuer/go/cloudbuild.yaml"
    IMAGE="${AR}/ansible-issuer:${TAG}"
    ;;
  verifier)
    CLOUDBUILD="ansible_zkpassport_verifier/cloudbuild.yaml"
    IMAGE="${AR}/ansible-zkpassport-verifier:${TAG}"
    ;;
  frontend)
    CLOUDBUILD="ansible_distribution_frontend/cloudbuild.yaml"
    IMAGE="${AR}/ansible-web:${TAG}"
    ;;
esac

log "building $SERVICE via $CLOUDBUILD (tag $TAG)"
gcloud builds submit "$REPO_ROOT" \
  --config="$REPO_ROOT/$CLOUDBUILD" \
  --substitutions=SHORT_SHA="$TAG" \
  --project "$PROJECT_ID"

# --- Migrations (relay/appview only) -------------------------------------------
# Runs the release migrator as a one-off Cloud Run Job before the deploy.
# GUARD: refuses to start while a previous migration execution is still running
# — two concurrent deploys racing migrations is undefined behaviour. This guard
# is best-effort (list-then-execute is not atomic); do not run two deploys of
# the same service at once.
run_migration_job() {
  local job="$1" binary="$2" secret="$3"

  local unfinished
  unfinished="$(gcloud run jobs executions list \
    --job="$job" --region "$REGION" --project "$PROJECT_ID" \
    --format='csv[no-heading](metadata.name,status.completionTime)' 2>/dev/null |
    awk -F, '$2 == "" {print $1}')" || unfinished=""
  if [ -n "$unfinished" ]; then
    die "migration execution(s) still running for $job: $unfinished — is another deploy in progress?"
  fi

  if gcloud run jobs describe "$job" --region "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
    log "updating migration job $job to $IMAGE"
    gcloud run jobs update "$job" \
      --image="$IMAGE" --region "$REGION" --project "$PROJECT_ID"
  else
    log "creating migration job $job"
    gcloud run jobs create "$job" \
      --image="$IMAGE" \
      --region "$REGION" \
      --project "$PROJECT_ID" \
      --vpc-connector="$VPC_CONNECTOR" \
      --vpc-egress=private-ranges-only \
      --set-secrets="DATABASE_URL=${secret}:latest" \
      --command="$binary" \
      --args="eval,${4}"
  fi

  log "executing migration job $job"
  gcloud run jobs execute "$job" --region "$REGION" --project "$PROJECT_ID" --wait
}

# --- Deploy ---------------------------------------------------------------------
# Env matrices mirror what each service actually reads:
#   relay:    ansible_relay/phoenix/config/runtime.exs
#   appview:  ansible_appview/phoenix/config/runtime.exs
#   issuer:   ansible_issuer/go/cmd/server/main.go
#   frontend: ansible_distribution_frontend/server.mjs
# `^;^` makes ';' the list separator so values may contain commas
# (WEB_ALLOWED_ORIGINS, UNIVERSAL_LINK_IOS_APP_IDS, ...).
case "$SERVICE" in
  relay)
    require_env RELAY_HOST WEB_HOST ISSUER_HOST ISSUER_PUBLIC_KEY_HEX \
      WEBAUTHN_RP_ID WEBAUTHN_ORIGIN
    run_migration_job ansible-relay-migrate /app/bin/ansible_relay \
      relay-database-url "AnsibleRelay.Release.migrate()"

    ENV_VARS="ISSUER_DID=did:web:${ISSUER_HOST}"
    ENV_VARS+=";ISSUER_PUBLIC_KEY_HEX=${ISSUER_PUBLIC_KEY_HEX}"
    ENV_VARS+=";RELAY_ORIGIN=https://${RELAY_HOST}"
    ENV_VARS+=";FORUM_HOST_BASE_URL=https://${RELAY_HOST}"
    ENV_VARS+=";WEB_ALLOWED_ORIGINS=${WEB_ALLOWED_ORIGINS:-https://${WEB_HOST}}"
    ENV_VARS+=";DATABASE_SSL=false"
    ENV_VARS+=";POOL_SIZE=${POOL_SIZE:-10}"
    ENV_VARS+=";WEBAUTHN_RP_ID=${WEBAUTHN_RP_ID}"
    ENV_VARS+=";WEBAUTHN_ORIGIN=${WEBAUTHN_ORIGIN}"
    ENV_VARS+=";WEBAUTHN_SYNC_CAPABILITY_REQUIRED=${WEBAUTHN_SYNC_CAPABILITY_REQUIRED:-false}"
    # Optional pass-throughs (universal links fail closed when unset; the ZKP
    # verification path stays disabled when unset — placeholders never boot).
    for OPT in UNIVERSAL_LINK_IOS_APP_IDS APP_LINK_ANDROID_PACKAGE \
      APP_LINK_ANDROID_SHA256_CERTS ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS REDIS_URL; do
      [ -z "${!OPT:-}" ] || ENV_VARS+=";${OPT}=${!OPT}"
    done

    log "deploying ansible-relay"
    gcloud run deploy ansible-relay \
      --image="$IMAGE" \
      --region "$REGION" \
      --project "$PROJECT_ID" \
      --platform=managed \
      --port=8080 \
      --vpc-connector="$VPC_CONNECTOR" \
      --vpc-egress=private-ranges-only \
      --min-instances=1 \
      --set-env-vars="^;^${ENV_VARS}" \
      --set-secrets="DATABASE_URL=relay-database-url:latest,ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX=relay-snapshot-signing-key:latest,SYNC_CAPABILITY_SECRET=relay-sync-capability-secret:latest" \
      --allow-unauthenticated
    ;;

  appview)
    require_env RELAY_HOST
    run_migration_job ansible-appview-migrate /app/bin/ansible_appview \
      appview-database-url "AnsibleAppview.Release.migrate()"

    # min=max=1: the ingest poller must be the single firehose consumer and the
    # in-process cache is single-instance (docs/deployment/scaling_operations.md
    # — set REDIS_URL + read replica before scaling out).
    log "deploying ansible-appview (pinned to 1 instance for ingest)"
    gcloud run deploy ansible-appview \
      --image="$IMAGE" \
      --region "$REGION" \
      --project "$PROJECT_ID" \
      --platform=managed \
      --port=8080 \
      --vpc-connector="$VPC_CONNECTOR" \
      --vpc-egress=private-ranges-only \
      --min-instances=1 --max-instances=1 \
      --set-env-vars="^;^RELAY_BASE_URL=https://${RELAY_HOST};INGEST_INTERVAL_MS=${INGEST_INTERVAL_MS:-5000}" \
      --set-secrets="DATABASE_URL=appview-database-url:latest" \
      --allow-unauthenticated
    ;;

  issuer)
    require_env ISSUER_HOST TW_PROVIDER_AUTH_URL
    BUCKET="${ISSUER_BUCKET:-${PROJECT_ID}-issuer-state}"

    ENV_VARS="ISSUER_DID=did:web:${ISSUER_HOST}"
    ENV_VARS+=";ISSUER_URL=https://${ISSUER_HOST}"
    ENV_VARS+=";PERSONHOOD_BINDING_STORE_PATH=/var/issuer-state/personhood.json"
    ENV_VARS+=";TW_PROVIDER_SESSION_STORE_PATH=/var/issuer-state/tw_provider_sessions.json"
    ENV_VARS+=";TW_PROVIDER_AUTH_URL=${TW_PROVIDER_AUTH_URL}"
    # `contract` is the only adapter that issues today; `production` fails closed.
    ENV_VARS+=";TW_PROVIDER_ADAPTER_MODE=${TW_PROVIDER_ADAPTER_MODE:-contract}"
    ENV_VARS+=";TW_PROVIDER_AUDIENCE=${TW_PROVIDER_AUDIENCE:-trisaura-issuer}"
    ENV_VARS+=";VC_TTL_DAYS=${VC_TTL_DAYS:-90}"
    ENV_VARS+=";OTP_TTL_SECONDS=${OTP_TTL_SECONDS:-300}"
    for OPT in PASSPORT_VERIFIER_URL PASSPORT_VERIFIER_AUDIENCE; do
      [ -z "${!OPT:-}" ] || ENV_VARS+=";${OPT}=${!OPT}"
    done
    # Pepper rotation: previous peppers stay valid for existing commitments.
    [ -z "${SUBJECT_COMMITMENT_PEPPER_PREVIOUS:-}" ] ||
      ENV_VARS+=";SUBJECT_COMMITMENT_PEPPER_PREVIOUS=${SUBJECT_COMMITMENT_PEPPER_PREVIOUS}"

    # --min/max-instances=1 is MANDATORY while the stores are file-backed (GCS
    # volume): they are not multi-instance safe. Only a Postgres-backed issuer
    # (DATABASE_URL set) may scale out — change the pin deliberately, with the
    # runbook, not by editing this default.
    log "deploying ansible-issuer (pinned to exactly 1 instance)"
    gcloud run deploy ansible-issuer \
      --image="$IMAGE" \
      --region "$REGION" \
      --project "$PROJECT_ID" \
      --platform=managed \
      --port=8080 \
      --min-instances=1 --max-instances=1 \
      --add-volume="name=issuer-state,type=cloud-storage,bucket=${BUCKET}" \
      --add-volume-mount="volume=issuer-state,mount-path=/var/issuer-state" \
      --set-env-vars="^;^${ENV_VARS}" \
      --set-secrets="ISSUER_PRIVATE_KEY_HEX=issuer-priv-key:latest,SUBJECT_COMMITMENT_PEPPER=subject-commitment-pepper:latest,TW_PROVIDER_SHARED_SECRET=tw-provider-shared-secret:latest,ISSUER_ADMIN_TOKEN=issuer-admin-token:latest" \
      --allow-unauthenticated
    ;;

  verifier)
    log "deploying ansible-zkpassport-verifier"
    gcloud run deploy ansible-zkpassport-verifier \
      --image="$IMAGE" \
      --region "$REGION" \
      --project "$PROJECT_ID" \
      --platform=managed \
      --port=8080 \
      --min-instances=1 \
      --memory=2Gi \
      --cpu=2 \
      --timeout=120 \
      --allow-unauthenticated
    ;;

  frontend)
    require_env RELAY_HOST
    ENV_VARS="RELAY_BASE_URL=https://${RELAY_HOST}"
    ENV_VARS+=";PUBLIC_RELAY_ORIGIN=${PUBLIC_RELAY_ORIGIN:-https://${RELAY_HOST}}"
    [ -z "${APPVIEW_HOST:-}" ] || ENV_VARS+=";APPVIEW_URL=https://${APPVIEW_HOST}"
    for OPT in UNIVERSAL_LINK_IOS_APP_IDS APP_LINK_ANDROID_PACKAGE APP_LINK_ANDROID_SHA256_CERTS; do
      [ -z "${!OPT:-}" ] || ENV_VARS+=";${OPT}=${!OPT}"
    done

    # Stateless: no instance pinning, no VPC (talks to the relay over https).
    log "deploying ansible-web"
    gcloud run deploy ansible-web \
      --image="$IMAGE" \
      --region "$REGION" \
      --project "$PROJECT_ID" \
      --platform=managed \
      --port=8080 \
      --set-env-vars="^;^${ENV_VARS}" \
      --allow-unauthenticated
    ;;
esac

log "$SERVICE deployed ($IMAGE). Run scripts/gcp/check_prod_readiness.sh next."
