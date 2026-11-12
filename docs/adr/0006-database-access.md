# ADR-0006: Separate migration and runtime database logins

- Status: Accepted (Phase 0 design; implementation Phase 1)
- Date: 2026-11-12
- Deciders: Architect, DB Agent, DevOps Agent, Security Agent, human gate
- Related: `PLAN.md` section 6 (database least privilege); `docs/THREAT_MODEL.md` sections 5.7, 5.9

## Context

PLAN.md requires the application database account to be least-privilege: no `sa`, no DDL
rights at runtime, and a separate migration account. The application must still create
schema in development and evolve it safely in production. The audit and ledger tables are
append-only, so the runtime login must be denied `UPDATE`/`DELETE` on them.

## Decision

Use two SQL Server principals per environment:

| Principal | Used by | Rights |
| :--- | :--- | :--- |
| `mini_erp_migrator` | Migration job only (deploy pipeline / local script) | `db_ddladmin`, `db_datareader`, `db_datawriter`, schema ownership as needed; no interactive app use |
| `mini_erp_app` | API runtime | `CONNECT`; `SELECT/INSERT/UPDATE` on business schemas; `INSERT/SELECT` on audit/ledger; `DENY UPDATE, DELETE` on append-only tables; `DENY ALTER, CONTROL`; no `db_owner`, no `db_ddladmin` |

Additional rules:

- The application **never runs migrations at startup**. CI produces an idempotent SQL
  script (`dotnet ef migrations script --idempotent`) as an artifact; the deploy job runs
  it with the migrator principal. Local development uses the same script or
  `dotnet ef database update` with the migrator connection string.
- Migrations are forward-only. An applied migration is never edited; corrections are new
  migrations. The Reviewer checks every migration for data-loss risk and lock duration.
- Connection strings are environment variables (`ConnectionStrings__Default` for the app,
  `ConnectionStrings__Migrator` for the job) and are never committed. Production prefers
  managed identity / integrated auth; development may use SQL auth with `Encrypt=true;
  TrustServerCertificate=true` against the local container.
- The SQL Server `sa` account is used **only** to bootstrap the container in development
  (create database and the two logins). It is never used by the API, never used in
  production, and its password lives only in the ignored `.env`.
- Schema layout: `app` (master data/documents), `inv` (stock ledger), `gl` (journal),
  `audit`, `identity` (ASP.NET Identity). Permissions are granted per schema, not
  database-wide `db_datareader`.
- Encryption: TDE is the baseline at-rest control for production databases and backups.
  Column-level encryption for tax IDs and bank details is an open decision (threat model
  M-05) to be settled before Phase 2 master data. TDE does not protect against a DBA, so
  column-level protection is preferred for the most sensitive fields if searchability
  allows.
- A startup/CI test connects as `mini_erp_app` and asserts it cannot `ALTER` a table or
  `DELETE` from audit/ledger tables.

## Consequences

Positive: a compromised API cannot change schema, drop tables or rewrite the ledger/audit
history; credential separation limits blast radius; migration execution is auditable and
reproducible. Negative: two secrets to manage and rotate, a deployment step that can fail
independently of the app, and local setup is slightly heavier. Stored procedures, if
added, must be granted explicitly to the app login.

## Alternatives considered

- One login with `db_owner`: rejected by PLAN.md and unacceptable for financial data.
- `sa` for simplicity: rejected; also blocked by container scanning and the threat model.
- Migrations at API startup: rejected; it gives the runtime DDL and creates race conditions
  with multiple replicas.
- Separate database per schema: unnecessary complexity for one tenant.

## Verification

- Phase 1 integration test: app login denied DDL and denied `DELETE` on `audit.AuditLog`.
- CI runs the idempotent migration script twice against a fresh Testcontainers database to
  prove idempotency.
- Reviewer checklist includes permission changes in every migration.
- Production runbook documents secret rotation and migration rollback (forward-fix only).
