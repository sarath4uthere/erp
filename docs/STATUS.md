# Build Status

Last updated: 2026-11-12
Current phase: **Phase 0 — Foundation (HUMAN GATE)**
Loop state: Phase 0 tasks and governance deliverables complete locally; CI first run and human review pending.

The Manager owns this file. Every task records owner, iteration count, gate verdicts and
evidence. Do not mark a task done without tests, Security and Reviewer evidence.

## Phase 0 task board

| Task | Owner | Iter | Status | Evidence |
| :--- | :--- | :---: | :--- | :--- |
| P0-01 Repository scaffold, PLAN.md, editor config, secrets policy | Manager / DevOps | 1 | DONE | `.gitignore`, `.editorconfig`, `.gitattributes`, `.env.example`; `docs/CONTRIBUTING.md`, `docs/SECURITY.md`, `docs/OPERATIONS.md`; `scripts/setup-dev.*`, `scripts/verify.*`; gitleaks config |
| P0-02 Layered .NET 8 solution + health endpoint + baseline middleware | Backend | 1 | DONE | `dotnet build` 0 warnings; 11 unit + 5 API/host tests green locally; SQL Testcontainers test gated to CI |
| P0-03 React + TypeScript + Vite SPA with health states | Frontend | 1 | DONE | lint, typecheck, 5 tests, build green; coverage 86.84% lines |
| P0-04 Docker Compose (SQL Server + API + web), non-root images | DevOps | 1 | DONE (static) | `docker compose config --quiet` green; image build/scan deferred to CI (no local engine) |
| P0-05 CI: build, tests, lint, SAST, dependency, secret and image scans | DevOps / Security | 1 | AUTHORED — first run pending push | `.github/workflows/ci.yml`; local equivalents green |
| P0-06 ADRs 0001-0007 + OpenAPI skeleton | Architect | 1 | DONE | 7 ADRs; Spectral 0 errors, 13 expected unused-component warnings |
| P0-07 STRIDE threat model | Security | 1 | DONE — human review pending | `docs/THREAT_MODEL.md` (444 lines), M-01..M-07 recorded |
| P0-08 Phase 0 verification and gate pack | QA / Reviewer | 1 | DONE (local scope) | `scripts/verify.ps1` green: restore, build 0 warnings, format, 16 tests, lint/typecheck/coverage/build, Spectral 0 errors, audits clean, compose config valid. gitleaks 8.30.1 scanned all commits: no leaks. Container build, image scan and CodeQL require CI. |

### Gate verdicts

| Gate | Verdict | Notes |
| :--- | :--- | :--- |
| QA | PASS (local scope) | Backend 11 unit + 5 API/host tests green; 1 SQL Server Testcontainers test is gated by `RUN_INTEGRATION_TESTS` and runs in CI. Frontend 5 tests green, 86.84% line coverage with an 80% line threshold. `scripts/verify.ps1` green. |
| Security | PASS WITH CONDITIONS | Threat model produced; dependency audits clean after two pins. High findings M-05/M-06/M-07 are Phase 0 accepted-risk decisions that require explicit human acknowledgement. |
| Reviewer | PASS WITH CONDITIONS | CI must be green on the first push; Docker image builds and Testcontainers have not executed locally. |

## Loop log (Phase 0)

| Iter | Event | Resolution |
| :---: | :--- | :--- |
| 1 | NuGet audit failed restore: transitive `System.Security.Cryptography.Pkcs` 8.0.1 (High + Moderate) via `Microsoft.Data.SqlClient` 7.1.1. | Pinned central transitive version 8.0.2. Restore clean. No severity threshold lowered. |
| 1 | Build failed: missing MVC usings in health controller. | Added `using Microsoft.AspNetCore.Mvc;`. |
| 1 | Analyzer `CA1307` and obsolete Testcontainers builder failed the warnings-as-errors build. | Used the comparison overload and the image-parameter constructor. |
| 1 | Frontend lint caught `setState` synchronously in an effect. | Moved the loading transition to the retry event handler; test still proves the retry path. |
| 1 | `npm audit` reported 10 moderate findings through `minimatch <= 11.0.0` (dev tooling ReDoS). | Added npm override to patched `minimatch` 11.0.8. Audit now reports 0 vulnerabilities at moderate+. |
| 1 | Windows application-control policy blocked test DLLs under `D:\ERP`. | Tests run with `--artifacts-path` in the approved temp directory; CI is unaffected. Recorded in CONTRIBUTING troubleshooting. |
| 1 | Docker engine is not running in this environment. | Compose config validated statically. Image build/scan and the SQL Server Testcontainers smoke test run in CI. Not waived; gate condition. |
| 2 | Governance docs and developer scripts were missing from the task board evidence. | Added `docs/CONTRIBUTING.md`, `docs/SECURITY.md`, `docs/OPERATIONS.md` (Phase 7 runbook stub with tickets), and cross-platform `scripts/setup-dev.*` / `scripts/verify.*`. |
| 2 | First `verify.ps1` run failed: `--artifacts-path` moved the restore assets while restore/build still used default `obj`. | Apply the artifacts path to `dotnet test` only and let it build into that path; build/format stay on the default tree. Script green. |
| 2 | Frontend coverage had no enforced threshold. | Added an 80% line threshold to `web/vite.config.ts`; measured 86.84% lines. Thresholds for branches/functions remain a Phase 1+ decision when business UI logic exists. |
| 2 | Phase 0 work was uncommitted, so task traceability and the history secret scan were untestable. | Created task-referenced commit history (`P0-01`..`P0-08`) on `main`; executable bits set on hook and shell scripts. gitleaks scanned all commits: no leaks. |

## Phase 0 exit checklist

- [x] Repository structure and solution layout match PLAN.md.
- [x] `.editorconfig`, `.gitattributes`, `.gitignore`, `.env.example`; no real secrets tracked; gitleaks clean across commit history.
- [x] Work is committed as a task-referenced history (`P0-01`..`P0-08`).
- [x] Docker Compose defines SQL Server 2022, API and web with health checks and non-root runtime images.
- [x] CI workflow contains build, tests, format, lint, CodeQL, gitleaks, NuGet/npm audits, Trivy fs+image, Spectral, compose validation, and a single `CI gate` job.
- [x] ADRs: stack, auth model, audit, money/decimal, soft delete, database access, API contract.
- [x] OpenAPI skeleton lints with zero errors.
- [x] Threat model exists and covers STRIDE, abuse cases, ASVS L2 mapping and accepted risks.
- [x] Contribution, security-reporting and operations docs exist; setup/verify scripts run on Windows and Linux/macOS.
- [x] Local verification green via `scripts/verify.ps1` (restore, build, format, 16 tests, lint, typecheck, coverage, build, Spectral, NuGet/npm audit, compose config).
- [ ] **CI green after first push to GitHub** (no remote configured yet).
- [ ] **Human review of the threat model and Phase 0 gate** (PLAN.md section 9).
- [ ] **Human acknowledges High findings M-05, M-06, M-07** or blocks Phase 1 until closed.
- [ ] Dependency register acknowledged by the human (Security Agent has recorded Phase 0 approvals).

## Open decisions for the human gate

1. TLS termination and certificate ownership (nginx vs upstream load balancer).
2. JWT signing-key storage and rotation (secret manager/KMS), and key overlap strategy.
3. Refresh-cookie domain strategy: same-origin only, or an `api.` subdomain.
4. Audit/financial/PII/backup retention periods and legal basis.
5. PII/tax-ID/bank-detail protection: TDE only, or column-level/Always Encrypted.
6. Backup encryption, key custody and restore-drill cadence.
7. Local ASP.NET Identity confirmed, or external OIDC provider.
8. PO approval thresholds and finance separation-of-duties rules.
9. Trusted proxy IPs/networks and `ForwardLimit` for client-IP audit correctness.
10. Phase 6 PDF generation: local renderer or remote service (SSRF/data-egress impact).

## Phase 1 backlog (created, not started)

| Task | Owner | Scope |
| :--- | :--- | :--- |
| P1-01 | Architect | Identity/RBAC schema, permission catalogue, OpenAPI auth operations |
| P1-02 | DB Agent | Identity + audit + revocation tables, migrations, filtered indexes |
| P1-03 | Backend | Login/MFA/refresh/logout, lockout, rate limiting, deny-by-default policies |
| P1-04 | Backend/DB | Audit interceptor + hash chain + append-only permissions |
| P1-05 | DevOps/DB | Migration job, `mini_erp_app`/`mini_erp_migrator` logins, trusted proxy config |
| P1-06 | Frontend | Login, MFA enrollment/challenge, silent refresh, forbidden states |
| P1-07 | QA | Authorization matrix (allowed/forbidden/anonymous) for 100% of endpoints |
| P1-08 | Security | Abuse suite SEC-AUTH*, SEC-JWT*, SEC-REFRESH*, SEC-CSRF*, SEC-MFA*, SEC-RATE*, SEC-AUDIT-001 |
| P1-09 | DevOps | Contract test (spec vs implementation), coverage gate >=80% on Application/Domain |
| P1-10 | Security | Close M-01 (CORS breadth), M-02 (proxy trust), M-03 (rate limits), M-04 (audit), M-07 (MFA) |

Deferred with tickets:

- `P1-COV`: enforce backend 80% line coverage on `MiniErp.Application` + `MiniErp.Domain` once business logic exists (the frontend 80% line threshold is active in `web/vite.config.ts`).
- `P7-SEC-01`: replace the placeholder security contact in `docs/SECURITY.md` before release.
- `P7-OPS-01`: complete `docs/OPERATIONS.md` runbook, backup/restore drill and incident process.
