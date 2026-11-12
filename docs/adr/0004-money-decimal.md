# ADR-0004: Money and quantity precision, rounding, and JSON transport

- Status: Accepted (Phase 0 design; enforced from Phase 2/5)
- Date: 2026-11-12
- Deciders: Architect, Security Agent, human gate (accounting review at Phase 5)
- Related: `PLAN.md` section 5; `docs/THREAT_MODEL.md` section 5.6

## Context

Floating-point money is a correctness and fraud risk. JavaScript numbers are IEEE-754
doubles and silently lose precision above 2^53 and on decimal fractions. The ERP stores
prices, costs, invoices, payments, journals, and stock quantities; totals must reconcile
exactly across documents, reports and the trial balance.

## Decision

### Database and .NET types

- Money: `DECIMAL(19,4)` in SQL Server, `decimal` in .NET. Maximum 15 integer digits and
  4 fractional digits.
- Quantities: `DECIMAL(18,4)`, `decimal` in .NET.
- Rates/percentages (tax, discount): `DECIMAL(9,6)` (e.g. `0.190000`), stored as a
  fraction, not a percentage. If a future requirement needs more precision, amend this
  ADR before the schema ships.
- No `float`, `double` or `real` anywhere in the domain, database, reports or frontend.
  A code-review and analyzer rule flags their use in money paths.

### JSON and API transport

- Money and quantities are serialized as **JSON strings**, not numbers, e.g.
  `"unitPrice": "19.9900"`, `"quantity": "2.5000"`.
- OpenAPI declares them as `type: string` with a decimal pattern and examples. The
  frontend never does arithmetic on them; it displays server-computed values and sends
  user-entered strings back. Authoritative totals are computed server-side.
- Dates are ISO 8601 UTC strings (`2026-11-12T10:15:30Z`) or date-only for business dates.
- Parsing uses `CultureInfo.InvariantCulture`; locale-dependent parsing is forbidden.
- A shared `Money`/`Quantity` value object (Domain) validates scale, range and
  non-negativity where required, and centralizes string conversion.

### Rounding

- Intermediate calculations use full .NET `decimal` precision.
- Rounding happens at **defined boundaries only**: invoice line net, line tax, document
  totals, payment allocations and journal amounts. Never round each intermediate step.
- Rounding mode: `MidpointRounding.AwayFromZero` (commercial rounding), applied once per
  boundary and documented in code. Banker's rounding is not used because invoice totals
  must match conventional customer expectations; the choice is tested.
- Sum of rounded lines is authoritative; the document total is not recomputed from an
  unrounded sum.
- Allocations (payments, discounts, landed cost) use a largest-remainder algorithm so the
  sum of allocated parts equals the allocated total exactly.
- `debit = credit` is compared exactly on `DECIMAL(19,4)` values; no tolerance.

### Database invariants

- CHECK constraints for non-negative amounts where the business rule requires it, and for
  quantity rules in the stock ledger.
- Journal posting is rejected in code and by the database if the sum of debits differs
  from the sum of credits for the entry.
- Currency is a single configured code (default `EUR`) stored on documents for
  traceability. Multi-currency is out of scope for v1; adding it requires a new ADR, FX
  rate storage and revaluation rules.

### Consequences

Positive: exact arithmetic, stable JSON across languages, no silent JavaScript rounding,
and one place to change rounding policy. Negative: strings require explicit parsing and
schema patterns; frontend forms need decimal-aware inputs; reports must aggregate with
SQL `DECIMAL`, not client-side math. Unit prices with 4 decimals may be insufficient for
some costing scenarios; changing to 6 requires an ADR amendment and migration.

## Alternatives considered

- JSON numbers: rejected due to JavaScript precision loss.
- Storing minor units as integers: exact but awkward for 4-decimal quantities and rates;
  rejected for consistency with PLAN.md.
- Banker's rounding: statistically better but surprising on invoices; rejected for v1.
- Floating point: rejected outright.

## Verification

- Property-based tests (Phase 5): for any set of lines, `sum(rounded lines) == document
  total`, and every journal entry has `debits == credits`.
- Contract tests assert money fields are strings matching the decimal pattern.
- A lint/review rule rejects `float`/`double` in money or quantity code.
- Accountant review at the Phase 5 human gate signs off on rounding and tax treatment.
