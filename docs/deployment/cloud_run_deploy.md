# Cloud Run Deployment Runbook (Genesis MVP)

Step-by-step `gcloud` commands to deploy the three Genesis services to Cloud Run
in one region:

- **Relay + Forum Host** (`ansible-relay`) — Elixir release, needs PostgreSQL.
- **Issuer** (`ansible-issuer`) — Go, single instance, persistent volume.
- **Distribution Frontend** (`ansible-web`) — Node static server + relay proxy.

> Scope: a single-region first deployment ("Genesis host"), not the multi-region
> GKE cluster described in `../architecture/genesis_hosting.md`. The issuer runs
> as exactly one instance — see "Durable Storage And Cloud Run" in
> [`tw_provider_issuer_deployment.md`](tw_provider_issuer_deployment.md).

All commands assume bash. Replace every `<...>` placeholder. Re-running the
idempotent create steps is safe (they no-op or error harmlessly if the resource
exists).

> See also: [`gcp_production_checklist.md`](gcp_production_checklist.md)
> (ordered go-live checklist), [`postgres_backup_pitr.md`](postgres_backup_pitr.md)
> (backups/PITR/restore drills), and `scripts/gcp/` (`provision.sh`,
> `deploy.sh <service>`, `check_prod_readiness.sh`) which script the steps
> below idempotently.

---

## 0. Variables and APIs

```bash
export PROJECT_ID="<your-gcp-project>"
export REGION="asia-east1"
export REPO="ansible"                       # Artifact Registry repo (matches cloudbuild.yaml)
export TAG="$(git rev-parse --short HEAD)"  # image tag for this deploy

# Public hostnames you will map to each service (set up DNS/SSL separately).
export RELAY_HOST="relay.elix.cool"
export ISSUER_HOST="issuer.elix.cool"
export WEB_HOST="forum.elix.cool"

export ISSUER_DID="did:web:${ISSUER_HOST}"
export AR="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}"

gcloud config set project "$PROJECT_ID"

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  vpcaccess.googleapis.com \
  storage.googleapis.com
```

---

## 1. Artifact Registry

```bash
gcloud artifacts repositories create "$REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Ansible / Tris-Aura service images"
```

---

## 2. Secrets (Secret Manager)

Generate the issuer keypair and pepper, then store the private material. **The
issuer public key half must be configured on the relay** as
`ISSUER_PUBLIC_KEY_HEX` (step 6) — they must come from the same keypair.

```bash
# Ed25519 issuer signing key (32-byte seed, 64 hex chars).
ISSUER_PRIV_HEX="$(openssl rand -hex 32)"
printf '%s' "$ISSUER_PRIV_HEX" | gcloud secrets create issuer-priv-key --data-file=-

# Subject commitment pepper.
openssl rand -hex 32 | gcloud secrets create subject-commitment-pepper --data-file=-

# TW provider contract-mode shared secret (staging / contract adapter).
openssl rand -hex 32 | gcloud secrets create tw-provider-shared-secret --data-file=-

# Relay op-snapshot Ed25519 signing seed — REQUIRED: the relay's prod boot
# raises without ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX (config/runtime.exs).
openssl rand -hex 32 | gcloud secrets create relay-snapshot-signing-key --data-file=-

# Issuer admin bearer token (enables the credential-revocation endpoint).
openssl rand -hex 32 | gcloud secrets create issuer-admin-token --data-file=-

# Relay PostgreSQL connection string (filled in after step 3).
# Created here as a placeholder; add the real value as a new version in step 3.
```

> Derive the issuer **public** key hex from `ISSUER_PRIV_HEX` with your Ed25519
> tooling (e.g. the issuer's own key utilities or `ansible_rust_core`) and export
> it as `ISSUER_PUB_HEX` for step 6. Do not commit either value.

Grant the Cloud Run runtime service account access (default compute SA shown;
use a dedicated SA in production):

```bash
export RUNTIME_SA="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')-compute@developer.gserviceaccount.com"

for S in issuer-priv-key subject-commitment-pepper tw-provider-shared-secret \
  relay-snapshot-signing-key issuer-admin-token relay-database-url; do
  gcloud secrets add-iam-policy-binding "$S" \
    --member="serviceAccount:${RUNTIME_SA}" \
    --role="roles/secretmanager.secretAccessor" 2>/dev/null || true
done
```

---

## 3. PostgreSQL for the relay (Cloud SQL + VPC)

Private IP + a Serverless VPC connector keeps `DATABASE_URL` a normal URL, so the
relay's `config/runtime.exs` needs no change.

```bash
# Serverless VPC Access connector (Cloud Run -> private IP).
gcloud compute networks vpc-access connectors create ansible-conn \
  --region="$REGION" \
  --network=default \
  --range=10.8.0.0/28

# Cloud SQL Postgres with private IP only. Daily backups + PITR are enabled
# from day one — see postgres_backup_pitr.md for retention, restore, and drills.
gcloud sql instances create ansible-relay-db \
  --database-version=POSTGRES_16 \
  --tier=db-custom-1-3840 \
  --region="$REGION" \
  --network=default \
  --no-assign-ip \
  --backup-start-time=17:00 \
  --retained-backups-count=14 \
  --enable-point-in-time-recovery \
  --retained-transaction-log-days=7

gcloud sql databases create ansible_relay --instance=ansible-relay-db

DB_PASS="$(openssl rand -hex 24)"
gcloud sql users create relay --instance=ansible-relay-db --password="$DB_PASS"

DB_PRIVATE_IP="$(gcloud sql instances describe ansible-relay-db \
  --format='value(ipAddresses[0].ipAddress)')"

# Store the connection string as a secret version.
printf 'ecto://relay:%s@%s/ansible_relay' "$DB_PASS" "$DB_PRIVATE_IP" \
  | gcloud secrets create relay-database-url --data-file=- 2>/dev/null \
  || printf 'ecto://relay:%s@%s/ansible_relay' "$DB_PASS" "$DB_PRIVATE_IP" \
       | gcloud secrets versions add relay-database-url --data-file=-
```

---

## 4. Issuer state bucket (GCS FUSE volume)

```bash
export ISSUER_BUCKET="${PROJECT_ID}-issuer-state"

gcloud storage buckets create "gs://${ISSUER_BUCKET}" \
  --location="$REGION" \
  --uniform-bucket-level-access

gcloud storage buckets add-iam-policy-binding "gs://${ISSUER_BUCKET}" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/storage.objectAdmin"
```

---

## 5. Build and push images

First-time manual build (passes `SHORT_SHA` that the trigger would normally
inject). Run from the repo root:

```bash
gcloud builds submit --config=ansible_relay/phoenix/cloudbuild.yaml \
  --substitutions=SHORT_SHA="$TAG" .

gcloud builds submit --config=ansible_issuer/go/cloudbuild.yaml \
  --substitutions=SHORT_SHA="$TAG" .

gcloud builds submit --config=ansible_distribution_frontend/cloudbuild.yaml \
  --substitutions=SHORT_SHA="$TAG" .
```

> For ongoing CI, create Cloud Build triggers using each `cloudbuild.yaml` and
> its "Included files" glob instead of manual submits.

---

## 6. Deploy the relay (+ Forum Host)

```bash
gcloud run deploy ansible-relay \
  --image="${AR}/ansible-relay:${TAG}" \
  --region="$REGION" \
  --platform=managed \
  --port=8080 \
  --vpc-connector=ansible-conn \
  --vpc-egress=private-ranges-only \
  --min-instances=1 \
  --set-env-vars="ISSUER_DID=${ISSUER_DID},ISSUER_PUBLIC_KEY_HEX=${ISSUER_PUB_HEX},RELAY_ORIGIN=https://${RELAY_HOST},FORUM_HOST_BASE_URL=https://${RELAY_HOST},WEB_ALLOWED_ORIGINS=https://${WEB_HOST},DATABASE_SSL=false,POOL_SIZE=10" \
  --set-secrets="DATABASE_URL=relay-database-url:latest,ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX=relay-snapshot-signing-key:latest" \
  --allow-unauthenticated
```

`ISSUER_PUBLIC_KEY_HEX` must be the public half of `issuer-priv-key`.
`WEB_ALLOWED_ORIGINS` must list the real frontend origin(s) — the default is
localhost and would block the deployed frontend.

### 6b. Universal links (optional, fail-closed)

Share URLs point at the host in `canonical_board_uri` (this relay, via
`FORUM_HOST_BASE_URL`). For the OS to open `https://<host>/boards/...` links
directly in the app, add these env vars to the relay deploy above (the web
frontend honours the same variables); each association file 404s until its
variables are set:

```bash
# iOS: TEAMID.bundleId, comma-separated.
UNIVERSAL_LINK_IOS_APP_IDS="T68YYD5V2Y.com.example.ansibleNode"
# Android: applicationId + signing-cert SHA-256 fingerprint(s).
APP_LINK_ANDROID_PACKAGE="io.trisaura.ansible_node"
APP_LINK_ANDROID_SHA256_CERTS="<keytool -list -v ... | grep SHA256>"
```

Verify: `curl https://${RELAY_HOST}/.well-known/apple-app-site-association`
and `curl https://${RELAY_HOST}/.well-known/assetlinks.json`.

### 6a. Run migrations (Cloud Run Job)

The release image has no `mix`; migrations run through `AnsibleRelay.Release`
(`ansible_relay/phoenix/lib/ansible_relay/release.ex`). Run them as a one-off job
on the same image **before** serving real traffic:

```bash
gcloud run jobs create ansible-relay-migrate \
  --image="${AR}/ansible-relay:${TAG}" \
  --region="$REGION" \
  --vpc-connector=ansible-conn \
  --vpc-egress=private-ranges-only \
  --set-secrets="DATABASE_URL=relay-database-url:latest" \
  --command="/app/bin/ansible_relay" \
  --args="eval,AnsibleRelay.Release.migrate()"

gcloud run jobs execute ansible-relay-migrate --region="$REGION" --wait
```

On later releases: update the job image, then execute it again.

```bash
gcloud run jobs update ansible-relay-migrate --image="${AR}/ansible-relay:${TAG}" --region="$REGION"
gcloud run jobs execute ansible-relay-migrate --region="$REGION" --wait
```

---

## 7. Deploy the issuer (single instance + GCS volume)

```bash
gcloud run deploy ansible-issuer \
  --image="${AR}/ansible-issuer:${TAG}" \
  --region="$REGION" \
  --platform=managed \
  --port=8080 \
  --min-instances=1 --max-instances=1 \
  --add-volume="name=issuer-state,type=cloud-storage,bucket=${ISSUER_BUCKET}" \
  --add-volume-mount="volume=issuer-state,mount-path=/var/issuer-state" \
  --set-env-vars="ISSUER_DID=${ISSUER_DID},ISSUER_URL=https://${ISSUER_HOST},PERSONHOOD_BINDING_STORE_PATH=/var/issuer-state/personhood.json,TW_PROVIDER_SESSION_STORE_PATH=/var/issuer-state/tw_provider_sessions.json,TW_PROVIDER_AUTH_URL=https://<provider-authorize-url>,TW_PROVIDER_ADAPTER_MODE=contract,TW_PROVIDER_AUDIENCE=trisaura-issuer,VC_TTL_DAYS=90,OTP_TTL_SECONDS=300" \
  --set-secrets="ISSUER_PRIVATE_KEY_HEX=issuer-priv-key:latest,SUBJECT_COMMITMENT_PEPPER=subject-commitment-pepper:latest,TW_PROVIDER_SHARED_SECRET=tw-provider-shared-secret:latest,ISSUER_ADMIN_TOKEN=issuer-admin-token:latest" \
  --allow-unauthenticated
```

Notes:
- `--min-instances=1 --max-instances=1` is **mandatory** — the in-memory store is
  not multi-instance safe (see the issuer deployment doc).
- `TW_PROVIDER_ADAPTER_MODE=contract` is the only adapter that issues today;
  `production` fails closed until the real TW provider adapter is implemented.
- Do **not** set `MOCK_MODE` in this deployment.
- MobileMoica RP stays disabled (no `MOBILEMOICA_RP_ENABLED`) until its approval
  artifacts and production adapter exist.
- Verify readiness: `curl https://${ISSUER_HOST}/readyz` should return `200`.

---

## 8. Deploy the frontend

```bash
gcloud run deploy ansible-web \
  --image="${AR}/ansible-web:${TAG}" \
  --region="$REGION" \
  --platform=managed \
  --port=8080 \
  --set-env-vars="RELAY_BASE_URL=https://${RELAY_HOST}" \
  --allow-unauthenticated
```

The browser only talks to the frontend origin; the frontend proxies `/api/*` to
`RELAY_BASE_URL`, which keeps the `SameSite=Strict` web-session cookie working.

---

## 8a. (Optional) AppView Component D — scalable following feed

Deploy this only when the following-feed load triggers in
`docs/superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md`
are hit. Until then the app uses the local Design-1 path and the AppView is not
required. The AppView ingests the relay op stream into a Postgres projection and
serves `/api/v1/timeline`.

```bash
# Own database for the AppView projection (rebuildable from relay ops).
gcloud sql databases create ansible_appview --instance=ansible-relay-db
printf 'ecto://relay:%s@%s/ansible_appview' "$DB_PASS" "$DB_PRIVATE_IP" \
  | gcloud secrets create appview-database-url --data-file=- 2>/dev/null \
  || printf 'ecto://relay:%s@%s/ansible_appview' "$DB_PASS" "$DB_PRIVATE_IP" \
       | gcloud secrets versions add appview-database-url --data-file=-
gcloud secrets add-iam-policy-binding appview-database-url \
  --member="serviceAccount:${RUNTIME_SA}" --role="roles/secretmanager.secretAccessor" 2>/dev/null || true

# Build (after creating a Cloud Build trigger, or manual):
gcloud builds submit --config=ansible_appview/phoenix/cloudbuild.yaml \
  --substitutions=SHORT_SHA="$TAG" .

# Migrate (Cloud Run Job on the same image).
gcloud run jobs create ansible-appview-migrate \
  --image="${AR}/ansible-appview:${TAG}" --region="$REGION" \
  --vpc-connector=ansible-conn --vpc-egress=private-ranges-only \
  --set-secrets="DATABASE_URL=appview-database-url:latest" \
  --command="/app/bin/ansible_appview" --args="eval,AnsibleAppview.Release.migrate()"
gcloud run jobs execute ansible-appview-migrate --region="$REGION" --wait

# Deploy. Single instance in Phase B: the ingest poller is the one firehose
# consumer (ingestion is idempotent by log_id, but one instance avoids wasted
# polling; the in-process cache, when added in Phase C, also requires it).
gcloud run deploy ansible-appview \
  --image="${AR}/ansible-appview:${TAG}" \
  --region="$REGION" --platform=managed --port=8080 \
  --vpc-connector=ansible-conn --vpc-egress=private-ranges-only \
  --min-instances=1 --max-instances=1 \
  --set-env-vars="RELAY_BASE_URL=https://${RELAY_HOST},INGEST_INTERVAL_MS=5000" \
  --set-secrets="DATABASE_URL=appview-database-url:latest" \
  --allow-unauthenticated
```

Point the app's `AppViewTimelineSource` transport at `https://<appview-host>` for
federated follows; `localOnly` follows keep using the local path. Rebuild the
projection any time with the Cloud Run Job command above swapped to
`--args="eval,AnsibleAppview.Release.rebuild()"`.

> Phase C (Pub/Sub firehose, fan-out-on-write, Redis cache, multi-instance,
> celebrity handling) is out of scope here — see the scale-design spec.

## 9. Domain mapping and did:web

Map each service to its hostname (or front them with a load balancer):

```bash
gcloud run domain-mappings create --service=ansible-relay --domain="$RELAY_HOST" --region="$REGION"
gcloud run domain-mappings create --service=ansible-issuer --domain="$ISSUER_HOST" --region="$REGION"
gcloud run domain-mappings create --service=ansible-web --domain="$WEB_HOST" --region="$REGION"
```

`ISSUER_DID=did:web:${ISSUER_HOST}` requires a DID document at
`https://${ISSUER_HOST}/.well-known/did.json` for any external party (e.g. the
app, or any W3C verifier) that resolves the issuer DID. The relay does **not**
need it (it trusts `ISSUER_PUBLIC_KEY_HEX` directly).

**The issuer now serves this file itself** at `GET /.well-known/did.json`,
derived from `ISSUER_DID` + the issuer key, e.g.:

```jsonc
{
  "@context": ["https://www.w3.org/ns/did/v1", "https://w3id.org/security/multikey/v1"],
  "id": "did:web:issuer.elix.cool",
  "verificationMethod": [{
    "id": "did:web:issuer.elix.cool#key-1",
    "type": "Multikey",
    "controller": "did:web:issuer.elix.cool",
    "publicKeyMultibase": "z6Mk…"  // multibase base58-btc, ed25519-pub multicodec
  }],
  "assertionMethod": ["did:web:issuer.elix.cool#key-1"]
}
```

Just ensure the issuer is reachable at `https://${ISSUER_HOST}` (domain mapping
above). Verify after deploy: `curl https://${ISSUER_HOST}/.well-known/did.json`.

---

## 10. Post-deploy verification

```bash
curl -fsS "https://${RELAY_HOST}/health"                 # relay alive
curl -fsS "https://${ISSUER_HOST}/healthz"               # issuer alive
curl -fsS "https://${ISSUER_HOST}/readyz"                # 200 = TW provider configured
curl -fsS "https://${RELAY_HOST}/api/v1/discovery"       # relay discovery payload
curl -fsS "https://${WEB_HOST}/"                         # frontend serves
```

Cross-service checklist:
- [ ] `ISSUER_PUBLIC_KEY_HEX` on the relay matches `issuer-priv-key`'s public half.
- [ ] `WEB_ALLOWED_ORIGINS`, `RELAY_ORIGIN`, `RELAY_BASE_URL` all use real https hosts (no localhost).
- [ ] Relay migration job ran successfully.
- [ ] Issuer is pinned to a single instance and `/readyz` is 200.
- [ ] `did.json` is published at the issuer host.
- [ ] ZKP verification keys: nothing to replace — the relay's prod boot overrides
      the dev placeholders in `config.exs` with an empty (disabled, fail-closed)
      registry and rejects placeholder values in
      `ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS`. Set that env var only when audited
      circuit keys ship (`config/runtime.exs`,
      `AnsibleRelay.Config.ZkpVerificationKeys`).
- [ ] Automated backups + PITR verified on `ansible-relay-db` and the first
      restore drill scheduled ([`postgres_backup_pitr.md`](postgres_backup_pitr.md)).
- [ ] Preflight passes: `scripts/gcp/check_prod_readiness.sh --project "$PROJECT_ID"`.
- [ ] SOSP pre-launch security gate cleared (`docs/security/sosp.md`).

---

## Rollback

```bash
# List revisions and route 100% back to a known-good one.
gcloud run revisions list --service=ansible-relay --region="$REGION"
gcloud run services update-traffic ansible-relay --region="$REGION" --to-revisions=<good-revision>=100
```

Apply the same pattern to `ansible-issuer` and `ansible-web`. Note that a relay
rollback does **not** roll back database migrations — write reversible migrations
and use `AnsibleRelay.Release.rollback/2` if a schema change must be undone.
```
