# ADR-0001: Layered monolith, .NET 8 API, React SPA, SQL Server 2022

- Status: Accepted (Phase 0, subject to the human gate)
- Date: 2026-11-12
- Deciders: Architect, Security Agent, human gate
- Related: `PLAN.md` sections 1, 4 (Phase 0), 5

## Context

PLAN.md fixes the stack: SQL Server 2022, ASP.NET Core 8, React + TypeScript + Vite,
ASP.NET Identity, xUnit, Testcontainers, GitHub Actions, Docker Compose. The product is a
single-tenant Mini-ERP for one small distributor, built by a small team with strict
quality gates. The domain has strong transactional invariants (stock ledger, double-entry
journal) and a moderate read/report load.

The architectural question is not *which stack* but *how the stack is shaped*: modular
monolith versus services, and how dependencies flow so business rules stay testable and
authorization cannot be bypassed.

## Decision

Build a **modular monolith** with four backend projects and one frontend app:

```
Domain          entities, value objects, invariants, domain services, domain events
Application     use cases, DTOs, validation, authorization requirements, ports
Infrastructure  EF Core DbContext, migrations, Identity stores, external adapters
Api             controllers, middleware, auth wiring, composition root
web             React 19 + TypeScript + Vite SPA
```

- Dependencies point inward: `Api -> Application -> Domain`; `Infrastructure -> Application`;
  `Domain` references no project. Infrastructure is composed only in `Api`.
- One deployable API and one static SPA. Containers: SQL Server, API, nginx-serving-SPA.
- **EF Core 8** is the data-access technology. Schema changes are EF Core migrations
  (forward-only) with `migrationBuilder.Sql(...)` for SQL Server constructs EF cannot
  express (filtered indexes, CHECK constraints, permission grants, hash-chain helpers).
  No runtime string-concatenated SQL. Parameterized raw SQL is allowed only in reviewed
  Infrastructure code or stored procedures.
- Controllers (attribute routing) expose the API; business rules never live in controllers.
- The SPA uses same-origin requests through nginx. It has no server-side rendering.
- Composition root validates the dependency graph at startup, and architecture tests
  (Phase 1) enforce project references.

## Consequences

Positive:

- One transaction can span business tables, the stock ledger, the journal and the audit
  log. This is essential for `debit = credit`, stock reconciliation and tamper-evident
  audit.
- One deployable unit, one migration stream, one set of logs and one security boundary.
- Domain/Application tests need no web host; integration tests use Testcontainers.
- EF Core gives parameterization by default and supports optimistic concurrency with
  `rowversion`.

Negative / risks:

- The monolith can erode into a layered mess. Mitigation: architecture tests, code review,
  and a hard rule that `Domain` has no infrastructure references.
- A single process is a single blast radius. Mitigation: least-privilege DB login, strict
  authorization, rate limits, container hardening; split only if measured load requires it.
- EF Core migrations can hide destructive changes. Mitigation: Reviewer checks every
  migration for data loss; CI applies migrations to a real SQL Server container.
- SQL Server licensing and container memory (dev default 2 GB) are real costs.

## Alternatives considered

- **Microservices**: rejected. Distributed transactions across stock, ledger and audit
  would add failure modes and operational cost with no benefit at this scale.
- **Dapper-only or raw ADO.NET**: rejected. More hand-written SQL raises injection and
  mapping risk; EF Core is sufficient for the query shapes in scope.
- **Next.js/SSR frontend**: rejected. The plan specifies React + Vite; server-driven forms
  and tables do not require SSR, and SSR would add a second runtime and auth surface.
- **DbUp instead of EF migrations**: viable, but it would split schema ownership from the
  EF model. EF migrations plus explicit SQL for invariants keeps one migration stream.

## Verification

- `dotnet build` enforces the project graph; Phase 1 adds NetArchTest rules.
- CI restores with lock files, builds, runs unit/integration tests and scans dependencies.
- A Testcontainers SQL Server test proves the migration path on every PR (Phase 1 onward).
