#!/usr/bin/env bash
# Idempotent one-time GCP provisioning for the Genesis stack
# (docs/deployment/cloud_run_deploy.md, docs/deployment/gcp_production_checklist.md).
#
# Creates (check-before-create, safe to re-run):
#   - required service APIs
#   - Artifact Registry docker repo
#   - private-services-access peering + Serverless VPC connector
#   - Cloud SQL Postgres 16 (PRIVATE IP ONLY, automated daily backups + PITR
#     enabled from day one — see docs/deployment/postgres_backup_pitr.md)
#   - databases ansible_relay + ansible_appview and the `relay` DB user
#   - Secret Manager secrets (random material generated in-process and piped
#     straight into Secret Manager; values are never printed)
#   - GCS bucket for issuer file-backed state
#   - IAM: runtime SA may read the secrets and write the issuer bucket
#
# Usage: scripts/gcp/provision.sh --project <id> [--region asia-east1]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/gcp/common.sh
source "$SCRIPT_DIR/common.sh"

parse_common_flags "$@"
[ ${#REST_ARGS[@]} -eq 0 ] || die "unexpected argument(s): ${REST_ARGS[*]}"
require_project

BUCKET="${ISSUER_BUCKET:-${PROJECT_ID}-issuer-state}"
PEERING_RANGE="google-managed-services-${NETWORK}"

log "project=$PROJECT_ID region=$REGION"

# --- APIs -------------------------------------------------------------------
log "enabling service APIs (no-op when already enabled)"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  vpcaccess.googleapis.com \
  servicenetworking.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  --project "$PROJECT_ID"

# --- Artifact Registry ------------------------------------------------------
if gcloud artifacts repositories describe "$REPO" \
  --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  log "artifact repo $REPO exists"
else
  log "creating artifact repo $REPO"
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker \
    --location "$REGION" \
    --project "$PROJECT_ID" \
    --description="Ansible / Tris-Aura service images"
fi

# --- Private services access (needed for Cloud SQL private IP) ---------------
if gcloud compute addresses describe "$PEERING_RANGE" \
  --global --project "$PROJECT_ID" >/dev/null 2>&1; then
  log "peering range $PEERING_RANGE exists"
else
  log "allocating private-services peering range $PEERING_RANGE"
  gcloud compute addresses create "$PEERING_RANGE" \
    --global \
    --purpose=VPC_PEERING \
    --prefix-length=16 \
    --network="$NETWORK" \
    --project "$PROJECT_ID"
fi

if gcloud services vpc-peerings list \
  --network="$NETWORK" --project "$PROJECT_ID" \
  --format='value(peering)' 2>/dev/null | grep -q servicenetworking; then
  log "servicenetworking peering exists"
else
  log "connecting servicenetworking peering"
  gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges="$PEERING_RANGE" \
    --network="$NETWORK" \
    --project "$PROJECT_ID"
fi

# --- Serverless VPC connector (Cloud Run -> private IP) ----------------------
if gcloud compute networks vpc-access connectors describe "$VPC_CONNECTOR" \
  --region "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  log "VPC connector $VPC_CONNECTOR exists"
else
  log "creating VPC connector $VPC_CONNECTOR"
  gcloud compute networks vpc-access connectors create "$VPC_CONNECTOR" \
    --region "$REGION" \
    --network="$NETWORK" \
    --range=10.8.0.0/28 \
    --project "$PROJECT_ID"
fi

# --- Cloud SQL: Postgres 16, private IP, backups + PITR from day one ---------
if gcloud sql instances describe "$SQL_INSTANCE" --project "$PROJECT_ID" >/dev/null 2>&1; then
  log "Cloud SQL instance $SQL_INSTANCE exists (backup/PITR settings NOT patched here;"
  log "verify per docs/deployment/postgres_backup_pitr.md)"
else
  log "creating Cloud SQL instance $SQL_INSTANCE (this takes several minutes)"
  gcloud sql instances create "$SQL_INSTANCE" \
    --database-version=POSTGRES_16 \
    --tier=db-custom-1-3840 \
    --region "$REGION" \
    --network="$NETWORK" \
    --no-assign-ip \
    --backup-start-time=17:00 \
    --retained-backups-count=14 \
    --enable-point-in-time-recovery \
    --retained-transaction-log-days=7 \
    --project "$PROJECT_ID"
fi

for DB in ansible_relay ansible_appview ansible_issuer; do
  if gcloud sql databases describe "$DB" \
    --instance "$SQL_INSTANCE" --project "$PROJECT_ID" >/dev/null 2>&1; then
    log "database $DB exists"
  else
    log "creating database $DB"
    gcloud sql databases create "$DB" --instance "$SQL_INSTANCE" --project "$PROJECT_ID"
  fi
done

DB_PRIVATE_IP="$(gcloud sql instances describe "$SQL_INSTANCE" \
  --project "$PROJECT_ID" --format='value(ipAddresses[0].ipAddress)')"

# The `relay` DB user owns both databases (runbook parity). Its password is
# generated once, piped straight into the *-database-url secrets, and never
# printed. If the user already exists we cannot recover the password, so the
# URL secrets are left alone (rotate manually if you need to re-key).
DB_USER_CREATED=false
DB_PASS=""
if gcloud sql users list --instance "$SQL_INSTANCE" --project "$PROJECT_ID" \
  --format='value(name)' | grep -qx relay; then
  log "DB user relay exists"
else
  log "creating DB user relay (password generated, stored only in Secret Manager)"
  DB_PASS="$(openssl rand -hex 24)"
  gcloud sql users create relay \
    --instance "$SQL_INSTANCE" \
    --password="$DB_PASS" \
    --project "$PROJECT_ID"
  DB_USER_CREATED=true
fi

create_db_url_secret() {
  local secret="$1" db="$2"
  if secret_exists "$secret"; then
    log "secret $secret exists"
    return
  fi
  if [ "$DB_USER_CREATED" != true ]; then
    warn "secret $secret is missing but the relay DB user already existed, so its"
    warn "password is unknown here. Reset it and add the secret version yourself:"
    warn "  gcloud sql users set-password relay --instance $SQL_INSTANCE --password=<new> --project $PROJECT_ID"
    warn "  printf 'ecto://relay:<new>@${DB_PRIVATE_IP}/${db}' | gcloud secrets create $secret --data-file=- --project $PROJECT_ID"
    PROVISION_INCOMPLETE=true
    return
  fi
  log "creating secret $secret"
  printf 'ecto://relay:%s@%s/%s' "$DB_PASS" "$DB_PRIVATE_IP" "$db" \
    | gcloud secrets create "$secret" --data-file=- --project "$PROJECT_ID"
}

# create_random_secret <name> <hex-bytes> — random hex material, never echoed.
create_random_secret() {
  local secret="$1" bytes="$2"
  if secret_exists "$secret"; then
    log "secret $secret exists"
  else
    log "creating secret $secret (${bytes}-byte random hex)"
    openssl rand -hex "$bytes" \
      | tr -d '\n' \
      | gcloud secrets create "$secret" --data-file=- --project "$PROJECT_ID"
  fi
}

PROVISION_INCOMPLETE=false
create_db_url_secret relay-database-url ansible_relay
create_db_url_secret appview-database-url ansible_appview

# Issuer personhood bindings and provider sessions require their own database
# principal. Do not reuse the relay credential: these stores contain private,
# security-critical duplicate-prevention commitments and have a separate
# operational boundary.
ISSUER_DB_USER_CREATED=false
ISSUER_DB_PASS=""
if gcloud sql users list --instance "$SQL_INSTANCE" --project "$PROJECT_ID" \
  --format='value(name)' | grep -qx issuer; then
  log "DB user issuer exists"
else
  log "creating DB user issuer (password generated, stored only in Secret Manager)"
  ISSUER_DB_PASS="Aa1!$(openssl rand -hex 22)"
  gcloud sql users create issuer \
    --instance "$SQL_INSTANCE" \
    --password="$ISSUER_DB_PASS" \
    --project "$PROJECT_ID"
  ISSUER_DB_USER_CREATED=true
fi

if secret_exists issuer-database-url; then
  log "secret issuer-database-url exists"
elif [ "$ISSUER_DB_USER_CREATED" = true ]; then
  log "creating secret issuer-database-url"
  printf 'postgres://issuer:%s@/ansible_issuer?host=%%2Fcloudsql%%2F%s%%3A%s%%3A%s' \
    "$ISSUER_DB_PASS" "$PROJECT_ID" "$REGION" "$SQL_INSTANCE" \
    | gcloud secrets create issuer-database-url --data-file=- --project "$PROJECT_ID"
else
  warn "secret issuer-database-url is missing but the issuer DB user already exists."
  warn "Reset that user's password and add a Cloud SQL Unix-socket PostgreSQL URL."
  PROVISION_INCOMPLETE=true
fi
unset ISSUER_DB_PASS

# Ed25519 issuer signing seed (private half; derive the public half for the
# relay with scripts/gcp/check_prod_readiness.sh or the checklist doc).
create_random_secret issuer-priv-key 32
# HMAC pepper for subject commitments (>= 32 bytes; issuer validates at boot).
create_random_secret subject-commitment-pepper 32
# TW provider contract-mode shared secret.
create_random_secret tw-provider-shared-secret 32
# Bearer token guarding the issuer's credential-revocation admin endpoint.
create_random_secret issuer-admin-token 32
# Relay op-snapshot Ed25519 signing seed (ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX;
# required at prod boot).
create_random_secret relay-snapshot-signing-key 32
# HMAC key for five-minute, DID-bound sync capabilities.
create_random_secret relay-sync-capability-secret 32

# --- Issuer state bucket ------------------------------------------------------
if gcloud storage buckets describe "gs://${BUCKET}" --project "$PROJECT_ID" >/dev/null 2>&1; then
  log "bucket gs://${BUCKET} exists"
else
  log "creating bucket gs://${BUCKET}"
  gcloud storage buckets create "gs://${BUCKET}" \
    --location "$REGION" \
    --uniform-bucket-level-access \
    --project "$PROJECT_ID"
fi

# --- IAM ----------------------------------------------------------------------
RUNTIME_SA="$(runtime_service_account)"
log "granting secret access + bucket write to $RUNTIME_SA"
for S in relay-database-url appview-database-url issuer-priv-key \
  subject-commitment-pepper tw-provider-shared-secret issuer-admin-token \
  relay-snapshot-signing-key relay-sync-capability-secret; do
  if secret_exists "$S"; then
    gcloud secrets add-iam-policy-binding "$S" \
      --member="serviceAccount:${RUNTIME_SA}" \
      --role="roles/secretmanager.secretAccessor" \
      --project "$PROJECT_ID" >/dev/null
  fi
done

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/storage.objectAdmin" \
  --project "$PROJECT_ID" >/dev/null

if [ "$PROVISION_INCOMPLETE" = true ]; then
  die "provisioning finished with manual follow-ups (see WARN lines above)"
fi

log "provisioning complete. Next: scripts/gcp/deploy.sh and"
log "docs/deployment/gcp_production_checklist.md"
