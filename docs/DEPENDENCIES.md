# Dependency register and approval policy

PLAN.md guardrail: **no new dependency without Security Agent approval (licence,
maintenance, known CVEs) and an ADR line.** The Security Agent records the decision here;
the human gate acknowledges the Phase 0 set. Every phase re-reviews the register.

## Policy

1. Prefer the platform: BCL, ASP.NET Core, EF Core, React. No package for something the
   framework already does safely.
2. Pin exact versions in `Directory.Packages.props` (NuGet) and `web/package.json` (npm).
   Commit lock files (`packages.lock.json`, `package-lock.json`); CI uses locked/ci mode.
3. Transitive vulnerabilities are pinned centrally (NuGet) or with npm `overrides`; never
   silence an advisory. `NuGetAudit` warnings are errors.
4. Required checks before approval: licence compatible with commercial use, active
   maintenance, no open Critical/High advisory, `dotnet list package --vulnerable` and
   `npm audit` clean at High, Trivy clean for the image/OS layer.
5. Dev-only tooling still needs approval: it runs with repository access in CI.
6. Container images are pinned by tag now and by digest before release (`P7-IMG-01`).

## Phase 0 approved set (Security Agent, 2026-11-12)

### .NET / NuGet

| Package | Version | Licence | Purpose | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Microsoft.AspNetCore.App (shared framework) | 8.0.34 | MIT | API runtime | Platform |
| Microsoft.NETCore.App (shared framework) | 8.0.34 | MIT | Runtime | Platform |
| Swashbuckle.AspNetCore | 6.9.0 | MIT | OpenAPI document + dev Swagger UI | Dev-facing; disabled outside Development |
| Microsoft.Data.SqlClient | 7.1.1 | MIT | SQL Server driver | Direct use in integration smoke test; EF Core adds it later |
| System.Security.Cryptography.Pkcs | 8.0.2 | MIT | Transitive pin | 8.0.1 had GHSA-2fmv-rv2c-59x7 / GHSA-846f-f764-76mx |
| Testcontainers.MsSql | 4.16.0 | MIT | Real SQL Server for integration tests | Docker required; CI only in Phase 0 |
| xunit | 2.9.3 | Apache-2.0 | Test framework | |
| xunit.runner.visualstudio | 2.8.2 | Apache-2.0 | Test discovery | |
| Microsoft.NET.Test.Sdk | 17.14.2 | MIT | Test host | |
| coverlet.collector | 6.0.4 | MIT | Coverage collection | Threshold enforced Phase 1 (`P1-COV`) |
| Microsoft.AspNetCore.Mvc.Testing | 8.0.34 | MIT | In-process API tests | |

Planned Phase 1 additions (not yet approved): EF Core 8 + SqlServer provider, Identity EF
stores, `Microsoft.AspNetCore.Authentication.JwtBearer`, rate-limiting (built-in),
FluentValidation or DataAnnotations (decide in PLAN), NetArchTest. Each must be added here
with a licence/CVE check before the first commit that uses it.

### npm / frontend

| Package | Version | Licence | Purpose | Notes |
| :--- | :--- | :--- | :--- | :--- |
| react / react-dom | 19.3.1 | MIT | UI | |
| vite | 7.3.8 | MIT | Build/dev server | |
| @vitejs/plugin-react | 5.2.0 | MIT | React transform | |
| typescript | 5.9.3 | Apache-2.0 | Types | Pinned below TS 6 for typescript-eslint compatibility |
| eslint | 10.14.0 | MIT | Lint | |
| @eslint/js | 10.0.1 | MIT | ESLint recommended config | |
| typescript-eslint | 8.72.2 | MIT | TS lint rules | |
| eslint-plugin-react-hooks | 7.1.1 | MIT | Hooks rules | |
| eslint-plugin-react-refresh | 0.5.7 | MIT | HMR safety | |
| globals | 17.14.0 | MIT | Browser globals | |
| vitest | 4.1.12 | MIT | Unit tests | |
| @vitest/coverage-v8 | 4.1.12 | MIT | Coverage | Thresholds active |
| jsdom | 31.0.0 | MIT | DOM test environment | |
| @testing-library/react | 16.3.3 | MIT | Component tests | |
| @testing-library/dom | 10.4.2 | MIT | Peer dependency | |
| @testing-library/jest-dom | 7.0.1 | MIT | DOM assertions | |
| @testing-library/user-event | 14.6.10 | MIT | Interaction tests | |
| minimatch (override) | 11.0.8 | ISC | Transitive pin | 7.0.0-11.0.0 affected by GHSA-g3hv-75wg-m249 (dev-only ReDoS) |

### CI tooling and actions

| Tool | Version | Licence | Purpose |
| :--- | :--- | :--- | :--- |
| gitleaks CLI | 8.30.1 | MIT | Secret scan (checksum pinned in CI) |
| Trivy action | 0.36.0 | Apache-2.0 | Filesystem + image scanning |
| CodeQL action | 4.39.3 | GitHub terms | SAST for C# and TypeScript |
| Spectral CLI | 6.17.1 | Apache-2.0 | OpenAPI lint (`npx`, pinned) |
| actions/checkout | 7.0.1 | MIT | Checkout |
| actions/setup-dotnet | 6.1.0 | MIT | .NET SDK + NuGet cache |
| actions/setup-node | 7.1.0 | MIT | Node + npm cache |
| actions/upload-artifact | 7.0.2 | MIT | Test/coverage artifacts |
| docker/setup-buildx-action | 4.4.1 | Apache-2.0 | Image build with cache |
| docker/build-push-action | 7.4.0 | Apache-2.0 | Image build |

### Container images

| Image | Tag | Licence/terms | Notes |
| :--- | :--- | :--- | :--- |
| mcr.microsoft.com/mssql/server | 2022-latest | Microsoft SQL Server EULA (Developer edition for dev) | Production licensing is a commercial decision; not redistributed |
| mcr.microsoft.com/dotnet/sdk | 8.0 | MIT | Build stage |
| mcr.microsoft.com/dotnet/aspnet | 8.0 | MIT | Runtime, non-root `APP_UID` |
| node | 24-alpine | MIT | Build stage |
| nginxinc/nginx-unprivileged | 1.27-alpine | BSD-2-Clause | Non-root static host + reverse proxy |

## Approval record

- 2026-11-12: Security Agent approves the Phase 0 set above for development and CI.
  Conditions: keep `NuGetAudit` failing on vulnerabilities; re-run audits on every PR;
  re-review this register at Phase 1 and before Phase 7 release.
- Human gate: acknowledge or reject this register as part of the Phase 0 sign-off.

## Known advisories resolved during Phase 0

| Advisory | Package | Severity | Resolution |
| :--- | :--- | :--- | :--- |
| GHSA-2fmv-rv2c-59x7, GHSA-846f-f764-76mx | System.Security.Cryptography.Pkcs 8.0.1 | Moderate + High | Pinned 8.0.2 centrally |
| GHSA-g3hv-75wg-m249 | minimatch < 11.0.1 | Moderate | npm override 11.0.8; dev-only tooling |
