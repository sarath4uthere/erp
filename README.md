# Mini-ERP

A small-distributor ERP: master data, inventory, purchasing, sales, invoicing with a
double-entry general ledger, reporting, and admin/security.

The authoritative build plan, agent roles, quality gates, and phase definitions live in
[`PLAN.md`](./PLAN.md). Live progress is tracked in [`docs/STATUS.md`](./docs/STATUS.md).

## Stack (fixed by PLAN.md)

| Layer | Choice |
| :--- | :--- |
| Database | SQL Server 2022 (Docker for dev), versioned migrations |
| Backend | ASP.NET Core 8 Web API (Api / Application / Domain / Infrastructure) |
| Frontend | React + TypeScript + Vite |
| Auth | ASP.NET Identity + short-lived JWT + refresh tokens, TOTP MFA for admins |
| Tests | xUnit, Testcontainers (real SQL Server), Playwright (E2E) |
| CI | GitHub Actions |
| Infra | Docker Compose (dev), deployable to any VM or cloud |

## Repository layout

```
src/Api                 HTTP surface: controllers, auth wiring, middleware
src/Application         Use cases, DTOs, validation, business rules
src/Domain              Entities, value objects, invariants, domain events
src/Infrastructure      EF Core, migrations runner, external services
tests/UnitTests         Fast domain/application tests
tests/IntegrationTests  Testcontainers + real SQL Server
tests/security          Abuse-case suites (Phase 1+)
web/                    React + TypeScript UI
db/design               Schema design artifacts (Architect)
db/migrations           Forward-only SQL migrations (DB Agent)
openapi/openapi.yaml    Contract-first API definition
docs/adr                Architecture decision records
docs/THREAT_MODEL.md    STRIDE threat model (Security Agent)
ops/docker              Container images
scripts                 Developer and CI helpers
```

## Prerequisites

- .NET SDK 8.0
- Node.js 22+ and npm 10+
- Docker with Compose v2 (SQL Server 2022 image)
- Git

## First-time setup

```powershell
pwsh ./scripts/setup-dev.ps1     # Windows (or powershell -File ./scripts/setup-dev.ps1)
./scripts/setup-dev.sh           # Linux/macOS
```

The script checks prerequisites, creates `.env` from `.env.example` when absent, installs
the pre-commit hook, restores NuGet packages, and installs web dependencies from the
lockfile. It never overwrites an existing `.env`.

## Quick start

```bash
# 1. Configure local environment (never commit .env)
cp .env.example .env

# 2. Start SQL Server + API + web
docker compose up --build

# 3. Or run the layers directly for development
dotnet run --project src/Api
npm --prefix web install
npm --prefix web run dev
```

Endpoints in the Phase 0 skeleton:

- API health: `GET http://localhost:8080/health`
- API OpenAPI (dev only): `http://localhost:8080/swagger`
- Web: `http://localhost:5173`

## Verify locally

```bash
pwsh ./scripts/verify.ps1         # Windows; add -IncludeIntegration with Docker
./scripts/verify.sh               # Linux/macOS; RUN_INTEGRATION_TESTS=true for Docker
```

The script mirrors the CI gates that can run locally. The individual commands are:

```bash
dotnet restore
dotnet build --configuration Release
dotnet test --configuration Release

npm --prefix web ci
npm --prefix web run lint
npm --prefix web run typecheck
npm --prefix web run test
npm --prefix web run build
```

Integration tests that require Docker are skipped unless `RUN_INTEGRATION_TESTS=true`.

## Security ground rules

- Never commit secrets. Only `.env.example` is tracked; `.env` is ignored.
- Application database accounts are least-privilege; migrations use a separate account
  (see `docs/adr/0006-database-access.md`).
- All API endpoints are deny-by-default from Phase 1 onward.
- Report vulnerabilities per `docs/SECURITY.md`, not in public issues.

## Contributing

Read [`docs/CONTRIBUTING.md`](./docs/CONTRIBUTING.md) for the branch naming, commit
convention, and the PLAN section 3 review loop. The short version: one task, one branch
(`feat/<phase>-<task>`), conventional commit referencing the task ID, and no merge
without QA + Security + Reviewer PASS.
