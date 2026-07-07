# PostgreSQL Backup & Point-in-Time Recovery (Cloud SQL)

Backup, PITR, restore, and drill procedures for the Genesis Cloud SQL instance
`ansible-relay-db` (region `asia-east1`), which hosts:

| Database | Service | Restore semantics |
|---|---|---|
| `ansible_relay` | ansible-relay (+ Forum Host) | **Source of truth.** Ops log, identity anchors, forum-host boards, moderation, snapshots. A restore is real, irreversible data loss for anything written after the restore point. |
| `ansible_appview` | ansible-appview | **Rebuildable projection** of relay ops + snapshot. Usually you do not restore it at all — you rebuild it (below). |
| (optional) issuer DB | ansible-issuer | Only exists if the issuer runs with `DATABASE_URL` (Postgres stores). Personhood bindings are irreplaceable — same care as the relay. Default deploy is file-backed on GCS instead. |

Companion docs: [`cloud_run_deploy.md`](cloud_run_deploy.md) (deploy runbook),
[`gcp_production_checklist.md`](gcp_production_checklist.md) (go-live order).
`scripts/gcp/provision.sh` creates new instances with everything in this doc
already enabled; the patch commands below are for instances created before it.

---

## 1. Enable automated backups + PITR

Target settings: daily automated backup, 14 retained backups, PITR with 7 days
of write-ahead-log retention (7 is the Cloud SQL Enterprise-edition maximum).

```bash
export PROJECT_ID="<your-gcp-project>"

gcloud sql instances patch ansible-relay-db \
  --project="$PROJECT_ID" \
  --backup-start-time=17:00 \
  --retained-backups-count=14 \
  --enable-point-in-time-recovery \
  --retained-transaction-log-days=7
```

Notes:

- `--backup-start-time` is UTC. `17:00` UTC = 01:00 Asia/Taipei (low traffic).
- Enabling PITR on an existing instance **restarts** it — schedule a short
  maintenance window; the relay reconnects automatically but requests in flight
  during the restart fail.
- PITR logs for Postgres are stored outside the instance disk (Cloud Storage)
  on current Cloud SQL versions, so log retention does not grow the data disk.

Verify:

```bash
gcloud sql instances describe ansible-relay-db --project="$PROJECT_ID" \
  --format='yaml(settings.backupConfiguration)'
# expect: enabled: true, pointInTimeRecoveryEnabled: true,
#         transactionLogRetentionDays: 7, retainedBackups.retainedBackups: 14
```

### On-demand backup (before risky changes)

Take one immediately before any manual migration, `rebuild()`, prune-window
change, or bulk moderation action:

```bash
gcloud sql backups create --instance=ansible-relay-db --project="$PROJECT_ID" \
  --description="pre-migration $(git rev-parse --short HEAD)"
```

---

## 2. Restore procedures

### 2a. PITR — clone to a NEW instance (preferred)

Cloning never touches the live instance, so it is the default move even under
pressure. The clone lands on the same VPC with a **new private IP**.

```bash
# 1. Pick the restore point (UTC, RFC 3339). Must be within the log-retention
#    window and after the oldest retained backup.
export RESTORE_AT="2026-07-07T02:00:00.000Z"

# 2. Clone.
gcloud sql instances clone ansible-relay-db ansible-relay-db-pitr \
  --project="$PROJECT_ID" \
  --point-in-time="$RESTORE_AT"

# 3. Get the clone's private IP.
CLONE_IP="$(gcloud sql instances describe ansible-relay-db-pitr \
  --project="$PROJECT_ID" --format='value(ipAddresses[0].ipAddress)')"

# 4. Sanity-check the clone BEFORE repointing anything (row counts, latest op
#    timestamps) from a VM/Cloud Shell on the VPC:
#    psql "postgresql://relay:<pass>@${CLONE_IP}/ansible_relay" \
#      -c "select max(inserted_at) from ops;"
```

**Repoint Cloud Run at the clone** — the DB URL lives in Secret Manager, and
Cloud Run resolves `:latest` only when a revision starts, so add a secret
version *and* force a new revision:

```bash
# relay
gcloud secrets versions access latest --secret=relay-database-url --project="$PROJECT_ID" \
  | sed "s#@[^/]*/#@${CLONE_IP}/#" \
  | gcloud secrets versions add relay-database-url --data-file=- --project="$PROJECT_ID"

gcloud run services update ansible-relay --region=asia-east1 --project="$PROJECT_ID" \
  --update-secrets=DATABASE_URL=relay-database-url:latest   # new revision -> re-reads secret
```

Repeat with `appview-database-url` / `ansible-appview` only if you are not
rebuilding the AppView (see 2c — rebuilding is usually better).

Afterwards: either keep the clone as the new primary (rename mentally, update
docs/alerts) and delete the old instance once confident, or use the clone for
data-surgery and copy rows back. Do not run two writable primaries.

### 2b. Restore a backup IN PLACE (destructive)

Overwrites the live instance with a nightly backup — only for total-loss cases
where the extra minutes of a clone are unacceptable and post-backup writes are
already known to be lost:

```bash
gcloud sql backups list --instance=ansible-relay-db --project="$PROJECT_ID"
gcloud sql backups restore <BACKUP_ID> \
  --restore-instance=ansible-relay-db --project="$PROJECT_ID"
```

All databases on the instance (`ansible_relay` **and** `ansible_appview`) are
rolled back together.

### 2c. What "restore" means per service

- **Relay**: the ops log is the network's source of truth. After a relay PITR,
  every op/anchor/board written after the restore point is gone — clients that
  already synced them will re-publish what they still hold locally on next
  sync (device-held data is authoritative per the constitution), but anything
  that existed only server-side is lost. Announce the restore point.
- **AppView**: a projection. After a relay restore — or appview corruption with
  a healthy relay — do **not** PITR the appview; rebuild it from the relay:

  ```bash
  gcloud run jobs update ansible-appview-migrate \
    --args="eval,AnsibleAppview.Release.rebuild()" \
    --region=asia-east1 --project="$PROJECT_ID"
  gcloud run jobs execute ansible-appview-migrate --region=asia-east1 --project="$PROJECT_ID" --wait
  # restore the job to its normal migrate args afterwards:
  gcloud run jobs update ansible-appview-migrate \
    --args="eval,AnsibleAppview.Release.migrate()" \
    --region=asia-east1 --project="$PROJECT_ID"
  ```

  Caveat: rebuild-from-zero needs the relay's op history back to the snapshot
  horizon — check `:snapshot_retention_days` before assuming a full rebuild is
  possible (`docs/deployment/scaling_operations.md`, follow-up 1).
- **Issuer**: default deploy stores state as JSON on the GCS bucket
  (`<project>-issuer-state`) — protect it with [Object Versioning]
  (`gcloud storage buckets update gs://<bucket> --versioning`) rather than this
  doc's SQL machinery. If `DATABASE_URL` is set, its database rides on the same
  instance/procedures above.

---

## 3. Backup verification cadence

Weekly (cheap, non-disruptive — put it in the ops rotation or a scheduled job):

```bash
# Most recent automated backup must be SUCCESSFUL and < 26h old.
gcloud sql backups list --instance=ansible-relay-db --project="$PROJECT_ID" \
  --limit=3 --format='table(id, windowStartTime, status)'

# PITR still enabled (a patch/failover can silently drop settings drift).
gcloud sql instances describe ansible-relay-db --project="$PROJECT_ID" \
  --format='value(settings.backupConfiguration.pointInTimeRecoveryEnabled)'
```

A backup that exists is not a backup that restores — hence the monthly drill.

## 4. Monthly restore drill

Do the drill on the production instance's real backups (clones don't touch the
primary). Time-box: ~30 min. Record date, operator, and timings in the ops log.

- [ ] Pick a restore point 1–24 h in the past; run the 2a clone command.
- [ ] Note time-to-clone-ready (baseline for real incidents).
- [ ] Connect to the clone from the VPC; verify:
  - [ ] `select count(*) from ops;` is plausible vs. production.
  - [ ] `select max(inserted_at) from ops;` is ≤ the restore point.
  - [ ] relay migrations table (`schema_migrations`) matches the deployed release.
- [ ] (Quarterly) point a **staging** relay revision at the clone and check
      `/readyz` + `GET /api/v1/discovery` serve real data.
- [ ] Verify the latest automated backup list shows no `FAILED` entries.
- [ ] Delete the clone: `gcloud sql instances delete ansible-relay-db-pitr`.
- [ ] File any gap found as a P1 ops issue.
