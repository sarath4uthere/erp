# ADR-0005: Soft delete, filtered uniqueness, and append-only exceptions

- Status: Accepted (Phase 0 design; enforced from Phase 2)
- Date: 2026-11-12
- Deciders: Architect, DB Agent, Security Agent, human gate
- Related: `PLAN.md` section 5; `docs/THREAT_MODEL.md` sections 5.7, 5.8

## Context

Master data and documents are referenced by history. Hard-deleting a customer, item or
warehouse breaks old invoices, stock movements and journal entries; reusing a SKU or tax
code after deletion creates ambiguity. At the same time, append-only financial and audit
records must never be deleted at all. The policy must be explicit so every migration and
query behaves consistently.

## Decision

### Soft delete applies to

Master data and editable business documents that must persist for history: customers,
suppliers, items, warehouses, tax rates, price lists, draft purchase/sales documents,
users (disable + anonymize rather than delete). Append-only records are **not**
soft-deletable: stock movements, journal entries/lines, audit log, posted invoice
snapshots. Corrections use reversing entries, never deletion.

### Columns and behaviour

Every soft-deletable table has:

- `IsDeleted bit NOT NULL DEFAULT 0`
- `DeletedAt datetime2(7) NULL`
- `DeletedBy uniqueidentifier NULL`
- Existing `CreatedAt/By`, `UpdatedAt/By`, `RowVersion` per PLAN.md section 5.

Deletion is an `UPDATE` that sets the flags, bumps `RowVersion`, and writes an audit event.
There is no hard `DELETE` from application code for these tables.

- EF Core global query filter: `!IsDeleted`. Queries must not see deleted rows by default.
- `IgnoreQueryFilters()` is allowed only in explicitly reviewed admin/restore/audit code.
- Foreign keys use `ON DELETE NO ACTION`. Because deletes are updates, FK integrity is
  preserved automatically.
- Unique indexes are **filtered**: `WHERE IsDeleted = 0` (for example `SKU`, tax code,
  customer number). This allows reuse of a code after an erroneous record is retired while
  keeping history.
- `IsActive` is separate from `IsDeleted`: deactivation stops new use but keeps the record
  selectable in history; deletion marks a mistake/duplicate and hides it by default.
- Deleting an entity referenced by an active document is rejected by the Application layer
  (409) unless the business rule allows retirement; the DB FK is the last line of defense.
- Restore requires the `masterdata.restore` permission, is audited, and re-validates
  uniqueness (the code may have been reused).

### Lifecycle and privacy

- Soft-deleted rows are excluded from lists, lookups and reports; historical documents
  still resolve the referenced row (the query filter is bypassed only for that
  resolution path, with a comment and test).
- GDPR/erasure requests: financial records are retained under legal basis; PII is
  anonymized in place (tombstone values), not hard-deleted, and the action is audited.
  Legal hold overrides erasure.
- Hard deletion is reserved for transient data (expired refresh tokens, idempotency
  records past retention, orphaned drafts with no references) via dedicated, audited jobs.
- No cascade delete of business records. Migrations that add soft-delete columns must be
  additive and safe on existing data (default 0, backfill, then index).

## Consequences

Positive: history stays intact, references never dangle, uniqueness is practical, and
accidental deletion is recoverable. Negative: every query must respect the filter; unique
indexes must be filtered; storage grows; "delete" semantics differ between master data and
ledgers, so UI wording must be explicit (Deactivate vs Delete). Bugs that bypass the
filter can leak deleted rows, hence tests.

## Alternatives considered

- Hard delete everywhere with nullable FKs: rejected; loses history and breaks reporting.
- Soft delete on every table including ledgers: rejected; a deletable ledger is not a
  ledger.
- Shadow/archive tables: more complex and duplicates the model; deferred unless volume
  demands it.
- Database-level row security for deleted rows: not needed if queries are filtered and
  tested; application filter plus permissions is sufficient for v1.

## Verification

- Tests assert deleted rows disappear from list/detail endpoints and remain resolvable
  from historical documents.
- Migration review checks filtered indexes and FK actions.
- Security test attempts to access a soft-deleted record by ID and expects 404 (no IDOR
  through the recycle bin).
- Restore test proves uniqueness re-validation and audit emission.
