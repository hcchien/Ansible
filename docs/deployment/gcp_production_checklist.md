# GCP Production Go-Live Checklist

Ordered, one-pass checklist for taking the Genesis stack to production on
Cloud Run. Each step links the doc/script that owns the detail:

- [`cloud_run_deploy.md`](cloud_run_deploy.md) — the per-command runbook.
- [`postgres_backup_pitr.md`](postgres_backup_pitr.md) — backups, PITR, drills.
- `scripts/gcp/` — `provision.sh`, `deploy.sh <service>`, `check_prod_readiness.sh`.

```bash
export PROJECT_ID="<your-gcp-project>"
export REGION="asia-east1"
export RELAY_HOST="relay.elix.cool"
export APPVIEW_HOST="appview.elix.cool"
export ISSUER_HOST="issuer.elix.cool"
export WEB_HOST="www.elix.cool"
export WEBAUTHN_RP_ID="elix.cool"
export WEBAUTHN_ORIGIN="https://www.elix.cool"
```

---

## 1. Provision infrastructure

- [ ] `scripts/gcp/provision.sh --project "$PROJECT_ID" --region "$REGION"`
      — APIs, Artifact Registry, VPC peering + connector, Cloud SQL Postgres 16
      (private IP, daily backups + 7-day PITR from day one), `ansible_relay` +
      `ansible_appview` DBs, Secret Manager secrets, issuer GCS bucket, IAM.
      Idempotent; re-run until clean.
- [ ] Confirm backup config took effect (`postgres_backup_pitr.md` §1 verify).
- [ ] (Recommended) enable Object Versioning on the issuer state bucket:
      `gcloud storage buckets update "gs://${PROJECT_ID}-issuer-state" --versioning`

## 2. Secrets and keys

`provision.sh` already generated random values for every secret below; this
step is about **verifying and wiring the public halves**. Rotate anything you
suspect was ever exposed.

| Secret | Consumed as | Notes |
|---|---|---|
| `issuer-priv-key` | development issuer `ISSUER_PRIVATE_KEY_HEX` | Ed25519 32-byte seed (64 hex). It must not be injected into production. |
| `subject-commitment-pepper` | issuer `SUBJECT_COMMITMENT_PEPPER` | ≥32 bytes; issuer refuses dev sentinels at boot. |
| `tw-provider-shared-secret` | issuer `TW_PROVIDER_SHARED_SECRET` | contract-adapter HMAC secret. |
| `issuer-admin-token` | issuer `ISSUER_ADMIN_TOKEN` | enables the revocation admin endpoint. |
| `relay-snapshot-signing-key` | relay `ANSIBLE_RELAY_SNAPSHOT_SIGNING_KEY_HEX` | required — prod boot raises without it. |
| `relay-sync-capability-secret` | relay `SYNC_CAPABILITY_SECRET` | HMAC key for short-lived, DID-bound sync capabilities. |
| `relay-database-url`, `appview-database-url` | `DATABASE_URL` | `ecto://relay:<pass>@<private-ip>/<db>` |

- [ ] Derive `ISSUER_PUBLIC_KEY_HEX` from the private seed (no extra deps —
      OpenSSL ≥1.1.1 + xxd; PKCS#8-wraps the seed and extracts the raw key):

  ```bash
  export ISSUER_PUBLIC_KEY_HEX="$(
    gcloud secrets versions access latest --secret=issuer-priv-key --project "$PROJECT_ID" \
      | { read -r SEED; printf '302e020100300506032b657004220420%s' "$SEED"; } \
      | xxd -r -p \
      | openssl pkey -inform DER -pubout -outform DER \
      | tail -c 32 | xxd -p -c 32
  )"
  ```

  Sanity: seed `9d61…7f60` (RFC 8032 vector 1) must yield `d75a…511a` —
  `check_prod_readiness.sh` self-tests this and re-verifies the pair post-deploy.
- [ ] If new keys were minted: generate with `openssl rand -hex 32` and pipe
      **directly** into `gcloud secrets versions add … --data-file=-` — never
      through shell history, files, or terminal output.
- [ ] Production issuer signing: configure `ISSUER_KMS_KEY_VERSION` to a
      versioned Cloud KMS `EC_SIGN_ED25519` key and grant only the issuer Cloud
      Run service account `roles/cloudkms.signerVerifier` on that key. Google
      Cloud KMS does not offer Ed25519 with HSM protection; its software
      protection still keeps private key material non-exportable and retains
      the `eddsa-jcs-2022` verification suite.
- [ ] Passport NFC issuance (only after its device-security tests pass): set
      `PASSPORT_VERIFIER_URL` to the **private** verifier service and set
      `PASSPORT_DID_RESOLVER_URL="https://$RELAY_HOST"`. Issuer refuses to
      start if only one is set. The verifier must use Cloud Run IAM and grant
      `roles/run.invoker` exclusively to the Issuer workload service account;
      never use `--allow-unauthenticated` for this service.
- [ ] ZKP verification keys: leave `ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS` unset.
      The relay's prod boot overrides the dev placeholders in `config.exs` with
      an empty (disabled, fail-closed) registry, and rejects placeholder or
      malformed values in the env var. Set it only when the ZKP anchor path
      ships with audited circuit verification keys.

## 3. Deploy services (order matters)

Relay first (everything else points at it), then issuer (so `did.json` and
`/readyz` are up before clients ask), then appview, then frontend.

- [ ] **Relay**:
  ```bash
  RELAY_HOST=$RELAY_HOST WEB_HOST=$WEB_HOST ISSUER_HOST=$ISSUER_HOST \
  ISSUER_PUBLIC_KEY_HEX=$ISSUER_PUBLIC_KEY_HEX \
  WEBAUTHN_RP_ID=$WEBAUTHN_RP_ID WEBAUTHN_ORIGIN=$WEBAUTHN_ORIGIN \
  WEBAUTHN_SYNC_CAPABILITY_REQUIRED=true \
  scripts/gcp/deploy.sh --project "$PROJECT_ID" --region "$REGION" relay
  ```
  (builds via cloudbuild.yaml → runs `ansible-relay-migrate` job → deploys;
  refuses to run while a previous migration execution is unfinished — do not
  race two deploys of the same service.)
- [ ] **Issuer** (pinned min=max=1 — file-backed stores are not multi-instance
      safe; only a `DATABASE_URL` Postgres issuer may scale):
  ```bash
  ISSUER_HOST=$ISSUER_HOST TW_PROVIDER_AUTH_URL="https://<provider-authorize-url>" \
  scripts/gcp/deploy.sh --project "$PROJECT_ID" --region "$REGION" issuer
  ```
- [ ] **AppView** (pinned min=max=1: single ingest poller + in-process cache):
  ```bash
  RELAY_HOST=$RELAY_HOST \
  scripts/gcp/deploy.sh --project "$PROJECT_ID" --region "$REGION" appview
  ```
- [ ] **Frontend** (stateless):
  ```bash
  RELAY_HOST=$RELAY_HOST \
  scripts/gcp/deploy.sh --project "$PROJECT_ID" --region "$REGION" frontend
  ```

## 4. Domains, DNS, universal links

- [ ] Domain mappings (`cloud_run_deploy.md` §9):
      `ansible-relay→$RELAY_HOST`, `ansible-issuer→$ISSUER_HOST`,
      `ansible-web→$WEB_HOST`; create the DNS records gcloud prints and wait
      for managed certs to go `ACTIVE`.
- [ ] `curl https://$ISSUER_HOST/.well-known/did.json` resolves (issuer serves
      it; required for `did:web:$ISSUER_HOST`).
- [ ] App-link association env on **both** relay and frontend deploys
      (fail-closed — each file 404s until set): `UNIVERSAL_LINK_IOS_APP_IDS`
      (TEAMID.bundleId), `APP_LINK_ANDROID_PACKAGE`,
      `APP_LINK_ANDROID_SHA256_CERTS` (signing-cert SHA-256). Re-run
      `deploy.sh relay` / `deploy.sh frontend` with them exported.
- [ ] Verify: `curl https://$RELAY_HOST/.well-known/apple-app-site-association`
      and `…/assetlinks.json` (and the same on `$WEB_HOST`).

## 5. Preflight + smoke tests

- [ ] `scripts/gcp/check_prod_readiness.sh --project "$PROJECT_ID" --region "$REGION"`
      — secrets present and non-placeholder, relay/issuer/appview env sane,
      issuer pinned to one instance, **issuer keypair match** (derives the
      public key from `issuer-priv-key` and compares to the relay's pinned
      `ISSUER_PUBLIC_KEY_HEX`). Must exit 0.
- [ ] Liveness/readiness/metrics per service:
  ```bash
  curl -fsS "https://$RELAY_HOST/health" && curl -fsS "https://$RELAY_HOST/readyz" && curl -fsS -o /dev/null "https://$RELAY_HOST/metrics"
  curl -fsS "https://$ISSUER_HOST/healthz" && curl -fsS "https://$ISSUER_HOST/readyz" && curl -fsS -o /dev/null "https://$ISSUER_HOST/metrics"
  curl -fsS "https://<appview-host>/health" && curl -fsS -o /dev/null "https://<appview-host>/metrics"
  curl -fsS "https://$WEB_HOST/healthz"    && curl -fsS -o /dev/null "https://$WEB_HOST/metrics"
  ```
- [ ] Relay discovery: `curl -fsS "https://$RELAY_HOST/api/v1/discovery"`
      advertises the real `https://$RELAY_HOST` origin (no localhost).
- [ ] End-to-end signed post: from a production-configured app build (or the
      second-test-user harness), register a passkey identity, publish a post to
      a public board, and confirm it appears via
      `https://$WEB_HOST` **and** in the appview
      (`/api/v1/explore`) with `author_tier` populated — this exercises
      passkey signing → relay signature verification → forum host → appview
      ingest in one pass.
- [ ] Rollback rehearsal: `gcloud run revisions list --service=ansible-relay`
      and confirm you can route 100% traffic to the previous revision
      (`cloud_run_deploy.md` §Rollback).

## 6. Backups verified

- [ ] `postgres_backup_pitr.md` §3 weekly verification run once by hand.
- [ ] First monthly restore drill scheduled (calendar + owner), checklist §4.
- [ ] On-demand backup taken **now** (pre-launch baseline):
      `gcloud sql backups create --instance=ansible-relay-db --description="go-live baseline"`

## 7. Known-open blockers (by design — decide, don't discover)

These fail closed in production. Going live means accepting them explicitly:

- **Email-credential flow is NON-FUNCTIONAL in prod.** The issuer's OTP flow
  has **no SMTP/SES sender** — the code is generated and stored, but only ever
  returned in the HTTP response under `MOCK_MODE` (which is refused on Cloud
  Run). Until an email sender lands, users cannot complete
  `POST /api/v1/vc/request` email verification. Do not advertise email
  credentials at launch.
- **TW provider `production` adapter fails closed.** Only
  `TW_PROVIDER_ADAPTER_MODE=contract` issues today; `production` refuses to
  configure until the real adapter is implemented
  ([`tw_provider_issuer_deployment.md`](tw_provider_issuer_deployment.md)).
- **Passport issuance returns 503** (`passport_verifier_unconfigured`): no real
  ZKP/NFC PassportBindingVerifier exists; deliberately unconfigured until the
  private verifier IAM, DID-control signature check, and real-device NFC test
  all pass. Do not set `PASSPORT_VERIFIER_URL` without
  `PASSPORT_DID_RESOLVER_URL`.
- **Relay ZKP verification path disabled** (step 2): prod boots with an empty
  verification-key registry until audited circuit keys are supplied.
- **MobileMoica RP stays disabled** (`MOBILEMOICA_RP_ENABLED` unset) until its
  approval artifacts + production adapter exist.
- **SOSP pre-launch gate** ([`../security/sosp.md`](../security/sosp.md)):
  P1–P3 audit items and the launch-gate checkboxes are tracked there — clear
  them before public announcement.
