# Contributing

This repository is built with the multi-agent loop defined in
[`PLAN.md`](../PLAN.md) section 3. Read that section before opening a change. The short
version is: one task, one branch, one task-referenced commit series, and no merge without
QA + Security + Reviewer PASS.

The agent that writes code never approves it. Backend, DB, Frontend, and DevOps output is
judged by QA, Security, and Reviewer. Manager keeps [`docs/STATUS.md`](./STATUS.md) current.

## Prerequisites

| Tool | Version | Notes |
| :--- | :--- | :--- |
| .NET SDK | 8.0.x | The repository pins `net8.0` and treats warnings as errors. |
| Node.js | >= 22.12.0 | CI uses Node 24. |
| npm | >= 10 | `npm ci` is required for reproducible installs. |
| Docker + Compose v2 | current | Needed for SQL Server, image builds, and Testcontainers. |
| Git | current | Pre-commit hook runs gitleaks when installed. |

## First-time setup

PowerShell 7 (`pwsh`) is recommended. Windows PowerShell 5.1 also works:

```powershell
pwsh ./scripts/setup-dev.ps1
# or
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/setup-dev.ps1
```

Linux/macOS:

```bash
./scripts/setup-dev.sh
```

The setup script copies `.env.example` to `.env` when `.env` is absent, installs the
pre-commit hook (`core.hooksPath=.githooks`), restores NuGet packages, and installs web
dependencies from the lockfile. It never overwrites an existing `.env`.

> `.env` is git-ignored. Never commit real secrets, tokens, certificates, or production
> connection strings. `.env.example` contains development-only placeholders.

## Build and test

Windows PowerShell:

```powershell
pwsh ./scripts/verify.ps1
# Windows PowerShell 5.1:
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/verify.ps1
# Include the Docker-backed SQL Server test:
pwsh ./scripts/verify.ps1 -IncludeIntegration
```

Linux/macOS:

```bash
./scripts/verify.sh
RUN_INTEGRATION_TESTS=true ./scripts/verify.sh
```

The individual commands are:

```bash
dotnet restore --locked-mode
dotnet build --no-restore --configuration Release
dotnet format MiniErp.sln --verify-no-changes --no-restore
dotnet test MiniErp.sln --no-build --configuration Release --filter "Category!=Integration"

npm --prefix web ci
npm --prefix web run lint
npm --prefix web run typecheck
npm --prefix web run test:coverage
npm --prefix web run build

npx --yes @stoplight/spectral-cli@6.17.1 lint openapi/openapi.yaml --fail-severity=error
docker compose --env-file .env.example config --quiet
```

Integration tests use Testcontainers and are skipped unless `RUN_INTEGRATION_TESTS=true`.
They require a running Docker engine and may take several minutes on the first pull.

### Windows: application-control workaround

Some managed Windows machines block test host DLLs written under the repository path
(`0x800711C7`, "An Application Control policy has blocked this file"). Run tests with an
artifacts directory on an approved local path:

```powershell
dotnet test MiniErp.sln --configuration Release `
  --artifacts-path "$env:TEMP\erp-artifacts"
```

`scripts/verify.ps1` accepts `-ArtifactsPath <dir>` and honours `ERP_ARTIFACTS_PATH`.
CI is not affected by this local policy.

## Branch and commit convention

- Branch: `feat/<phase>-<task>` (for example `feat/p1-03-auth-endpoints`).
- One logical task per branch; keep unrelated refactors out.
- Commit subject: `<type>(<task-id>): <summary>`, for example
  `feat(P1-03): add refresh-token rotation and reuse detection`.
- Accepted types: `feat`, `fix`, `test`, `docs`, `build`, `ci`, `refactor`, `chore`,
  `security`.
- Every commit references a task ID. A commit without one is rejected at review.
- Keep commits small and buildable. Do not commit generated output (`bin`, `obj`, `dist`,
  `coverage`), local `.env`, or IDE state.

## Task workflow

1. **PLAN (Architect):** record acceptance criteria, data-model changes, OpenAPI changes,
   and security notes. A new dependency needs Security approval and an ADR line
   (see [`docs/DEPENDENCIES.md`](./DEPENDENCIES.md)).
2. **BUILD (DB/Backend/Frontend/DevOps):** implement on the feature branch. Update the
   OpenAPI contract before the frontend consumes it.
3. **TEST (QA):** unit and integration tests, plus E2E where applicable. Coverage on
   business logic must be at least 80% and must not decrease.
4. **SECURITY (Security):** threat-model delta, SAST/dependency/secret/image scans, and
   abuse-case tests. Any open Critical or High finding blocks merge.
5. **REVIEW (Reviewer):** compare against the task spec, ADRs, contract, naming, and
   migration safety. Verdict is PASS or FAIL with itemized reasons.
6. **MERGE:** only after QA + Security + Reviewer PASS. Manager updates `docs/STATUS.md`.

Maximum three build-fix iterations per task. On the fourth failure, stop and write
`docs/BLOCKED_<task>.md` describing the failure, attempted fixes, and the decision needed.

## Change rules

- Do not delete tests, weaken assertions, disable scanners, or lower coverage thresholds
  to obtain a pass. This is an automatic FAIL.
- Do not bypass authorization. New endpoints are deny-by-default and must declare their
  permission explicitly.
- Do not write raw string-concatenated SQL. Use EF Core or parameterized commands.
- Money is `DECIMAL(19,4)`; quantities are `DECIMAL(18,4)`. Never use floating point for
  either. Serialize money as JSON strings at the contract boundary.
- List endpoints require pagination with a server-enforced maximum page size.
- Errors use RFC 7807 problem details. Never return stack traces, SQL text, or secrets.
- Schema changes ship as forward-only migrations with invariant checks. The application
  never runs migrations at startup.
- Update the OpenAPI contract and ADRs in the same task when behavior or architecture
  changes. An undocumented endpoint is a defect.

## Pull request checklist

- [ ] Task ID in the title and every commit.
- [ ] Acceptance criteria and test evidence in the description.
- [ ] `scripts/verify` green locally (or CI-only failures explained and ticketed).
- [ ] Tests added/updated; no skipped or weakened assertions.
- [ ] Authorization and audit coverage for every new endpoint or mutation.
- [ ] OpenAPI updated; contract lint has zero errors.
- [ ] Migration reviewed for locking, data loss, and rollback/forward-fix plan.
- [ ] No secrets, PII, or debug output added.
- [ ] `docs/STATUS.md` updated by Manager after merge.
- [ ] Threat model or dependency register updated when the change affects them.

## Local troubleshooting

| Symptom | Cause / fix |
| :--- | :--- |
| `0x800711C7` during `dotnet test` | Application-control policy. Use `--artifacts-path` on an approved path. |
| Compose fails to start SQL Server | Check `MSSQL_SA_PASSWORD` meets complexity rules and Docker has enough memory. |
| `npm ci` fails after dependency edit | Regenerate and commit `web/package-lock.json`; do not hand-edit it. |
| `dotnet restore --locked-mode` fails | A project file changed without updating `packages.lock.json`; restore normally, verify the diff, and commit the lock file. |
| Pre-commit says gitleaks is missing | Install gitleaks or ignore it locally; CI still enforces the secret scan. |
| Frontend tests cannot resolve `jsdom` | Run `npm --prefix web ci`; do not install ad-hoc packages. |
