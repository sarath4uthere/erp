# ADR-0003: Append-only, hash-chained audit log

- Status: Accepted (Phase 0 design; implementation Phase 1)
- Date: 2026-11-12
- Deciders: Architect, Security Agent, DB Agent, human gate
- Related: `PLAN.md` sections 4 (Phase 1), 5, 6; `docs/THREAT_MODEL.md` sections 5.8, 5.7

## Context

Every financial and master-data change must answer who, what, when, from where, and what
the value was before/after. The audit log is itself a target: an attacker who can update
or delete rows defeats non-repudiation. The plan requires an append-only table, before and
after values, timestamp, IP, correlation ID, and a separate read permission.

## Decision

### Storage

Create an `audit.AuditLog` table with these columns (exact DDL is owned by the DB Agent):

| Column | Type | Notes |
| :--- | :--- | :--- |
| `Id` | `bigint identity` | monotonic per database |
| `OccurredAt` | `datetime2(7)` | UTC, server-generated |
| `ActorUserId` | `uniqueidentifier null` | null for system/migration actions |
| `ActorDisplay` | `nvarchar(200)` | snapshot, survives user deletion |
| `Action` | `nvarchar(100)` | stable verb, e.g. `customer.updated` |
| `EntityType` | `nvarchar(100)` | stable name, not CLR type |
| `EntityId` | `nvarchar(100)` | string to cover GUID/int/composite keys |
| `BeforeJson` | `nvarchar(max) null` | masked, canonical JSON |
| `AfterJson` | `nvarchar(max) null` | masked, canonical JSON |
| `IpAddress` | `varbinary(16)` or `nvarchar(45)` | normalized; never X-Forwarded-For unless trusted |
| `UserAgent` | `nvarchar(512) null` | truncated; optional privacy review |
| `CorrelationId` | `nvarchar(64)` | validated allow-list characters |
| `PrevHash` | `binary(32)` | 32 zero bytes for the first row |
| `Hash` | `binary(32)` | SHA-256 over the canonical record |
| `SchemaVersion` | `int` | hash canonicalization version |

### Hash chain

`Hash = SHA256(PrevHash || canonical_json(record without Hash))` where canonical JSON has
sorted property names, invariant number formatting, UTF-8 without BOM, and `null` for
absent values. Money and quantities are strings to avoid float drift. Inserting a record
takes the previous `Hash` under a serialized lock (`sp_getapplock` on `audit-chain` or a
`UPDLOCK, HOLDLOCK` read of the tail row) so two writers cannot fork the chain. Chain
verification is a test/job that recomputes from the first row and reports the first break.

This is **tamper-evident**, not tamper-proof. A DBA with full control can rebuild the
chain. Phase 7 optionally ships the tail hash to append-only external storage for an
independent anchor.

### Capture mechanism

- EF Core `SaveChanges` interceptor captures changes for entities opting into auditing,
  producing a field-level diff from an explicit allow-list. It never serializes whole EF
  entities (mass-assignment and secret-leak risk).
- Domain/application code can emit explicit semantic events (e.g. `invoice.posted`,
  `period.closed`) with a typed payload; these are preferred over raw diffs for financial
  documents.
- Masking runs before serialization: password hashes, TOTP secrets, recovery codes,
  refresh tokens, tax IDs, bank account numbers and any field marked sensitive are
  replaced with a stable mask (e.g. `"***"` or last-4 only where policy allows). Secrets
  must never enter `BeforeJson`/`AfterJson`.
- The audit row is written **inside the same database transaction** as the business
  change. If the audit insert fails, the business change rolls back. There is no
  "best effort" audit path for state changes.
- Authorization denials and authentication events are audited without before/after.
- No audit rows for reads by default; `audit.read` access to the audit API is itself
  audited (metadata only).

### Database permissions

The runtime login receives `INSERT` and `SELECT` on `audit.AuditLog` and is explicitly
`DENY UPDATE, DELETE`. The migration login owns the schema. Application code exposes no
update/delete path. A retention job runs under a separate, audited principal; automatic
purge stays disabled until the human approves a retention policy.

### Reading and retention

- Reading requires the `audit.read` permission (Admin/auditor); it is not implied by any
  other role. Listing is paginated and filterable by entity, actor, action and date range.
- Export requires a separate `audit.export` permission and is itself audited.
- Default retention is **7 years**, configurable per deployment after legal review.
  Deletion, if ever approved, must be a documented, audited archival process, not an
  application delete.

## Consequences

Positive: consistent attribution, strong evidence, and a chain that makes silent edits
detectable. Negative: hash chaining serializes audit writes and can become a throughput
bottleneck; at this scale it is acceptable. JSON diffs increase storage; retention and
partitioning are Phase 7 concerns. Masking must be maintained as new sensitive fields are
added, and a missed field is a security defect.

## Alternatives considered

- Database triggers only: rejected as the sole mechanism; triggers are hard to test, do
  not know the authenticated application actor, and are easy to disable by a DBA.
- Change Data Capture (CDC): useful for forensics but does not capture the application
  actor, semantic action or masked before/after; CDC also depends on SQL Server Agent.
- External log-only audit (e.g. append-only object storage): deferred to Phase 7 as an
  additional anchor; the transactional DB row is required for consistency.
- No hash chain: rejected; the plan explicitly asks for tamper evidence.

## Verification

- `SEC-AUDIT-001`: the runtime login cannot `UPDATE`/`DELETE` audit or ledger rows.
- Integration test: a failed business transaction leaves no audit row; a successful one
  leaves exactly one with the right actor/correlation ID.
- Chain verification test re-computes hashes after inserts and after an attempted manual
  tamper (using a privileged test connection) and detects the break.
- Reviewer checks every new audited entity has a masking classification.
