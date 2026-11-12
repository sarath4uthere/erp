# Architecture Decision Records

ADRs are numbered, immutable once accepted, and referenced from `PLAN.md` and
`docs/STATUS.md`. Supersede rather than rewrite: add a new ADR and mark the old one
`Superseded by ADR-XXXX`.

| ADR | Title | Status | Phase |
| :--- | :--- | :--- | :--- |
| [0001](./0001-stack.md) | Layered monolith, .NET 8 + React + SQL Server | Accepted (human gate) | 0 |
| [0002](./0002-auth-model.md) | Identity, JWT access tokens, rotating refresh cookies, TOTP | Accepted (human gate) | 1 |
| [0003](./0003-audit-approach.md) | Append-only hash-chained audit log | Accepted (human gate) | 1 |
| [0004](./0004-money-decimal.md) | Money and quantity precision, rounding, JSON transport | Accepted (human gate) | 5 |
| [0005](./0005-soft-delete.md) | Soft delete, filtered uniqueness, append-only exceptions | Accepted (human gate) | 2 |
| [0006](./0006-database-access.md) | Migration vs runtime database logins | Accepted (human gate) | 1 |
| [0007](./0007-api-contract.md) | OpenAPI-first contract, errors, pagination, idempotency | Accepted (human gate) | 1 |

## Template

```markdown
# ADR-XXXX: Title

- Status: Proposed | Accepted | Superseded by ADR-YYYY
- Date: YYYY-MM-DD
- Deciders: Architect, Security Agent, human gate
- Related: PLAN.md section N, ADR-YYYY

## Context

What forces are at play? Constraints from PLAN.md, scale, team, compliance.

## Decision

The choice, stated in the active voice.

## Consequences

Positive, negative, operational and security consequences. What becomes harder.

## Alternatives considered

Option, why rejected.

## Verification

Tests, scans or reviews that prove the decision is implemented.
```
