# Operations Runbook

> **Status: Phase 0 stub — not production ready.** Deployment topology, TLS, key
> management, backups, monitoring, and incident response are Phase 7 deliverables. Items
> marked `P7-OPS-*` are tracked in [`docs/STATUS.md`](./STATUS.md). Do not deploy this
> project to a production environment until the Phase 7 human gate is approved.

## 1. Scope and environments

| Environment | Status | Database | Purpose |
| :--- | :--- | :--- | :--- |
| Local | Available | SQL Server 2022 in Docker | Development and tests |
| CI | Available | Testcontainers SQL Server per job | Automated verification |
| Staging | Not defined (`P7-OPS-02`) | Not defined | Pre-release validation |
| Production | Not defined (`P7-OPS-02`) | Not defined | Customer use |

Local secrets live in `.env` (git-ignored) copied from `.env.example`. Every value in
`.env.example` is a development placeholder and must never be reused outside local
development.

## 2. Local stack

```bash
cp .env.example .env          # first run only
docker compose up --build     # SQL Server + API + web
docker compose ps
docker compose logs -f api
docker compose down           # keep the named volume
docker compose down --volumes # destructive: deletes local SQL data
```

| Service | Address | Health |
| :--- | :--- | :--- |
| API | `http://localhost:8080` | `GET /health` |
| API OpenAPI (Development only) | `http://localhost:8080/swagger` | — |
| Web | `http://localhost:5173` | SPA health panel |
| SQL Server | `localhost:1433` | Compose health check |

Run layers directly instead of containers:

```bash
dotnet run --project src/Api
npm --prefix web ci && npm --prefix web run dev
```

The Vite dev server proxies `/api` and `/health` to the API target
(`VITE_DEV_API_TARGET`, default `http://localhost:8080`).

## 3. Configuration and secrets

- Configuration is supplied by environment variables; no secrets are baked into images.
- `JWT_SIGNING_KEY` in `.env.example` is a placeholder. Generate a unique value locally
  and never reuse it across environments.
- Production requires a secret manager/KMS, key rotation, and an overlap strategy
  (`P7-OPS-03`). Key custody is an open Phase 0 human decision.
- `.env` must never be committed. A leaked secret is rotated first, then removed from
  history; deletion alone is insufficient.
- Database logins: `mini_erp_migrator` owns schema changes; `mini_erp_app` is the
  least-privilege runtime login (ADR-0006). Credentials are provisioned per environment.

## 4. Build, test, and release gates

```bash
pwsh ./scripts/verify.ps1                 # Windows
./scripts/verify.sh                       # Linux/macOS
RUN_INTEGRATION_TESTS=true ./scripts/verify.sh
```

CI (`.github/workflows/ci.yml`) is the release authority. Merge requires all jobs green:
backend build/format/tests, Testcontainers integration, frontend lint/typecheck/tests/
build, gitleaks, NuGet/npm audits, CodeQL, Trivy filesystem and image scans, OpenAPI lint,
compose validation, and the aggregate `CI gate` job.

Release requirements before Phase 7 approval:

- no open Critical/High security finding;
- threat model reviewed with accepted risks signed off;
- backup/restore drill completed;
- performance test on realistic volumes completed;
- staged deployment with rollback proven.

## 5. Database operations

- Migrations are versioned, forward-only, and applied by a dedicated migration job using
  `mini_erp_migrator`. The API never migrates at startup.
- Take a backup (or snapshot for local/dev) before applying a migration to shared data.
- Test migrations against a restored copy of realistic data, including rollback/forward-fix.
- Never edit an applied migration. Add a new migration.
- Financial ledgers and audit rows are append-only. Do not delete them; use soft delete for
  master data and documents (ADR-0003, ADR-0005).
- Period close locks accounting periods; corrections require a reversing entry, not an edit.

Migration job, backup schedule, and restore procedure are `P7-OPS-01`/`P7-OPS-04`
deliverables.

## 6. Observability

Current baseline: structured application logs, correlation IDs propagated per request, and
anonymous liveness endpoints `/health` and `/healthz` that expose no dependency details.

Production requirements (`P7-OPS-05`):

- centralized log retention with access control and PII redaction;
- metrics and alerting for availability, error rate, latency, auth failures, lockouts, and
  database saturation;
- readiness checks separated from liveness;
- audit-log integrity monitoring (hash chain verification);
- dashboards for business-critical failures (posting, stock, invoicing).

Never log passwords, tokens, refresh cookies, full tax IDs, bank details, or raw request
bodies that may contain them.

## 7. Backup, restore, and retention (`P7-OPS-04`, `P7-OPS-06`)

Not implemented in Phase 0. Before production:

- define RPO/RTO and retention periods for financial records, audit logs, PII, and backups;
- encrypt backups at rest and in transit; define key custody and who may restore;
- keep an offsite/immutable copy protected from ransomware and accidental deletion;
- restore to an isolated environment on a fixed cadence and record the result;
- prove audit and ledger integrity after restore;
- document legal/accounting retention and erasure handling for soft-deleted records.

## 8. Incident response (`P7-OPS-07`)

1. **Detect and classify:** confirm the incident, assess severity and data impact, open a
   private record, and preserve evidence.
2. **Contain:** revoke sessions/refresh-token families, rotate affected credentials, isolate
   hosts, and disable compromised accounts.
3. **Eradicate and recover:** patch the root cause, restore from a verified backup if
   needed, and verify audit/ledger integrity.
4. **Notify:** follow legal/contractual obligations. The security contact and breach
   notification process must be defined before release (`P7-SEC-01`).
5. **Learn:** add a regression/abuse test and update the threat model, runbook, and
   `docs/STATUS.md`.

Contact details, escalation rota, and legal notification timelines are placeholders until
`P7-OPS-07` is complete.

## 9. Rollback and disaster recovery

- Application: redeploy the previous known-good image; database migrations are
  forward-only, so prepare a forward fix rather than a destructive down migration.
- Database: restore the verified pre-change backup; confirm login permissions, audit chain,
  and trial balance afterward.
- Keys: retain the previous signing key only for the documented overlap window; revoke
  refresh families when compromise is suspected.
- Document every recovery exercise with date, operator, duration, and gaps found.

## 10. Open operational decisions

The Phase 0 human gate must resolve or explicitly defer:

1. TLS termination and certificate ownership.
2. JWT signing-key storage, rotation, and overlap.
3. Refresh-cookie domain strategy.
4. Audit/financial/PII/backup retention and legal basis.
5. TDE versus column-level/Always Encrypted for tax IDs and bank details.
6. Backup encryption, key custody, and restore-drill cadence.
7. Local ASP.NET Identity versus external OIDC.
8. PO approval thresholds and finance separation-of-duties.
9. Trusted proxy IPs/networks and forwarded-header limit.
10. Phase 6 PDF generation: local renderer versus remote service.

See [`docs/THREAT_MODEL.md`](./THREAT_MODEL.md) section 11 and `docs/STATUS.md`.

## 11. Phase 7 operations backlog

| Ticket | Deliverable |
| :--- | :--- |
| `P7-OPS-01` | Complete this runbook: topology, deploy/rollback, migration job, on-call. |
| `P7-OPS-02` | Define staging and production environments with least-privilege access. |
| `P7-OPS-03` | Secret manager/KMS integration, key rotation, and break-glass procedure. |
| `P7-OPS-04` | Automated encrypted backups, retention, and a passed restore drill. |
| `P7-OPS-05` | Centralized logging, metrics, alerting, and audit-integrity monitoring. |
| `P7-OPS-06` | Retention/erasure policy for financial records, audit, PII, and backups. |
| `P7-OPS-07` | Incident response plan, contacts, escalation, and breach notification. |
| `P7-OPS-08` | Performance and capacity test on realistic volumes; publish limits. |
