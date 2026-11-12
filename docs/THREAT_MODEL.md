# Mini-ERP Threat Model

## Document control

| Field | Value |
| :--- | :--- |
| Title | Mini-ERP Threat Model (STRIDE) |
| Version | 0.1 |
| Date | 2026-11-12 |
| Owner | Security Agent |
| Reviewers | Human gate (Phase 0), Architect, Reviewer |
| Status | Draft for Phase 0 human review |
| Standard | OWASP ASVS 4.0.3 Level 2 target; OWASP Top 10 (2021) minimum |
| Scope | Phase 0 architecture and the planned Phase 1-7 Mini-ERP system described in `PLAN.md` |
| Out of scope | Multi-company, multi-currency, manufacturing/BOM, payroll, mobile apps, third-party integrations, physical security, cloud-provider controls |

This document records threats and planned controls. Controls marked **planned (Phase N)** do not exist today. Phase 0 exposes only anonymous health endpoints plus Development-only Swagger; no business data or identity endpoints exist yet.

## 1. Security objectives and assumptions

Objectives:

1. Preserve the confidentiality and integrity of financial records, stock movements, journal entries, pricing/cost data, and customer/supplier data.
2. Ensure every business action is authenticated, authorized, attributable, and recorded in an append-only audit trail.
3. Prevent privilege escalation, separation-of-duties bypass, IDOR, injection, token replay, and tampering with ledgers or audit records.
4. Keep credentials, tokens, signing keys, and backups out of source control, logs, browser persistent storage, and unauthorized hands.
5. Detect and contain compromise through correlation IDs, structured logs, audit verification, and CI/container scanning.
6. Maintain availability of the API and database for a small distributor without exposing unnecessary attack surface.

Assumptions:

| ID | Assumption | Consequence if false |
| :--- | :--- | :--- |
| A-01 | Single tenant; one organisation and one legal entity. | Cross-tenant isolation threats are not modelled; a future multi-tenant change reopens authorization and data-isolation analysis. |
| A-02 | Administrators are trusted but authenticated, MFA-protected, and audited. | A malicious admin is partially in scope; database/backup administrators remain trusted for v1. |
| A-03 | No internet-facing file upload in v1. Reports export CSV/PDF; nothing is accepted from browsers as a file. | File-upload malware, polyglot, and storage traversal threats are deferred. |
| A-04 | Single currency (EUR) and single company; money is `DECIMAL(19,4)` and quantities `DECIMAL(18,4)`. | Multi-currency and FX-rate threats are out of scope. |
| A-05 | TLS is terminated by nginx or an upstream load balancer; the API is not directly internet-facing. | Without a trusted proxy boundary, forwarded-header, HSTS, and client-IP controls are invalid. |
| A-06 | ASP.NET Identity is the v1 identity store in the application SQL Server; no external IdP is selected yet. | If an external IdP is adopted, MFA, lockout, token, and account-recovery responsibilities must be reassigned. |
| A-07 | The SPA and API are same-origin through nginx; CORS remains fail-closed for any other origin. | A cross-origin SPA deployment changes cookie, CSRF, and CORS assumptions. |
| A-08 | Only the application and migration logins access the database; DBAs are trusted operational staff. | A malicious DBA can bypass application controls; external audit shipping is required to reduce this residual risk. |

## 2. Assets inventory

| Asset | Location | Sensitivity | Why it matters | Primary controls |
| :--- | :--- | :--- | :--- | :--- |
| User credentials and password hashes | ASP.NET Identity tables in SQL Server | Critical | Account takeover and lateral movement | PBKDF2 Identity hasher, min length 12, lockout, MFA, no password logging |
| JWT signing key | Secret store or environment; never repo | Critical | Forging any user or permission | Managed secret, rotation runbook, single pinned algorithm, gitleaks |
| Refresh tokens and token families | Hashed/opaque server-side state; HttpOnly cookie in browser | Critical | Persistent session hijack | Rotation on every use, reuse detection, family revocation, `Secure` `HttpOnly` `SameSite=Strict` |
| Customer/supplier PII and tax IDs | Master Data tables | High | Privacy harm, fraud, regulatory exposure | Least-privilege access, masking, encryption-at-rest decision pending, audit reads |
| Bank details | Supplier/customer payment records | Critical | Payment diversion | Column-level encryption or TDE decision, masking, restricted permissions, audit |
| Pricing, cost, margin data | Items, price lists, sales/purchase documents | High | Competitive harm and fraud | Field-level authorization, report row limits, no logging of payloads |
| Stock ledger and quantity on hand | Inventory tables, derived balances | High | Inventory theft and financial misstatement | Append-only movements, DB constraints, concurrency tests, audit |
| Journal entries and trial balance | GL tables | Critical | Financial misstatement and fraud | Debit=credit enforced in code and DB, period locks, separation of duties, immutable postings |
| Audit log | Append-only `AuditLog` table and future external sink | Critical | Non-repudiation and investigation | Hash chain, `DENY UPDATE/DELETE`, `audit.read`, external shipping (Phase 7) |
| Backups | Backup storage, offsite/immutable copy | Critical | Total data loss or extortion | Encryption, key custody, access control, restore drill, immutability |
| CI/CD secrets and tokens | GitHub Actions secrets/OIDC; registries | Critical | Supply-chain compromise and production deployment | OIDC, least privilege, environment approvals, secret scanning, no long-lived keys |
| Container images and build artifacts | Registry, CI cache | High | Backdoored runtime or dependency | Digest pinning, Trivy, provenance/attestation, minimal non-root images |
| Correlation IDs and logs | Log pipeline/SIEM | Medium | Detection and investigation; possible PII spill | Structured logging, redaction, retention, access control |

## 3. Actors and entry points

| Actor | Trust | Entry points | Notes |
| :--- | :--- | :--- | :--- |
| Anonymous internet user | Untrusted | `GET /health`, `GET /healthz`, future `/api/auth/*`; TLS/nginx | Can probe, brute force, flood, and attempt protocol abuse. No business data access. |
| Authenticated clerk | Low privilege, authenticated | SPA -> `/api/*` with JWT; refresh cookie | Sales/purchasing/master-data operations per permission; object scope enforced server-side. |
| Warehouse operator | Low privilege, authenticated | SPA stock operations and movements | Cannot post journals or approve purchases; quantity integrity critical. |
| Finance user | Elevated business privilege, MFA | Invoicing, GL, reports, payments | MFA mandatory; posting and reversal duties separated; audit read only if granted. |
| Administrator | High privilege, MFA | Admin/security module, user/role management, configuration | MFA mandatory; admin actions audited; cannot silently grant self permissions. |
| Migration job | Highly privileged, non-interactive | Dedicated DDL login, migration runner | Runs only in deploy pipeline; no runtime use; credentials separate from API. |
| CI/CD pipeline | High trust, automated | Git push/PR, registries, deploy target | Branch protection, least-privilege token, environment approval, signed artifacts (Phase 7). |
| Backup operator | High trust, human/automated | SQL Server backup and restore tooling, key store | Can read backups; must not bypass audit or alter production data. |
| Malicious insider | Authenticated but adversarial | Any permitted UI/API/database path | Goal: fraud, data theft, covering tracks. Controls: least privilege, SoD, immutable audit, anomaly alerts. |

## 4. Trust boundaries and data flows

```text
+-----------------------------+          +--------------------------------------+
| Browser / React 19 SPA      |          | Internet / untrusted clients         |
| - access JWT in JS memory   |          | - anonymous probes, login attempts   |
| - refresh cookie (HttpOnly) |          +------------------+-------------------+
+--------------+--------------+                             |
               | HTTPS same-origin                          | HTTPS
               v                                            v
+-----------------------------------------------------------------------------+
| Edge: TLS termination, nginx                                                |
| - serves SPA, proxies /api and /health, adds CSP/HSTS/security headers      |
| - trusted-proxy boundary; client IP and scheme derived here                 |
+-----------------------------------+-----------------------------------------+
                                    | HTTP (private network)
                                    v
+-----------------------------------------------------------------------------+
| API: ASP.NET Core 8 (Api / Application / Domain / Infrastructure)           |
| - correlation, security headers, CORS, rate limits, authN/authZ, validation |
| - problem details; no stack traces; audit emission                          |
+----------------+--------------------------------+---------------------------+
                 |                                |
                 | EF Core, least-privilege       | Identity operations
                 v                                v
+---------------------------------+   +---------------------------------------+
| SQL Server 2022                 |   | ASP.NET Identity tables               |
| - business schema, GL, audit    |   | - users, roles, claims, tokens        |
| - runtime login: no DDL         |   | - same instance, restricted schema    |
| - migration login: DDL only     |   +---------------------------------------+
+----------------+----------------+
                 |
                 | encrypted backup path
                 v
+-----------------------------------------------------------------------------+
| Backup storage (offsite/immutable)  <--- Backup operator / restore tooling  |
+-----------------------------------------------------------------------------+

CI/CD: Git push -> GitHub Actions (build, test, CodeQL, gitleaks, dependency audit,
Trivy, Spectral, compose validation) -> registry -> approved deploy -> migration job.
```

Data-flow notes:

1. The browser never talks directly to SQL Server or Identity tables; all access is mediated by the API.
2. The access JWT lives only in JavaScript memory. The refresh token is an opaque cookie scoped to `/api/auth`, rotated on every use, and never readable by JavaScript.
3. nginx is the only public listener. `/api` and `/health` are proxied same-origin; the SPA fallback must not serve arbitrary files or proxy unintended paths.
4. The API uses a least-privilege runtime login with explicit DML grants and `DENY DELETE` on append-only tables. A separate migration login owns DDL and is used only by the migration job.
5. Audit writes and business writes must be committed atomically where the business action requires an audit record; audit is not best-effort for privileged or financial actions.
6. Backups leave the database host through an encrypted, access-controlled path. Key custody and restore ownership are open decisions (Section 12).

## 5. STRIDE analysis

Rating method: likelihood (L/M/H) x impact (L/M/H), using Low = L/L or L/M or M/L; Medium = M/M, H/L, or L/H; High = H/M or M/H; Critical = H/H. Category abbreviations are the STRIDE letters: S = Spoofing, T = Tampering, R = Repudiation, I = Information disclosure, D = Denial of service, E = Elevation of privilege. Severity policy follows `PLAN.md` section 6: Critical/High block merge; Medium requires a fix in phase or a human-approved ADR exception; Low goes to backlog.

### 5.1 Browser / SPA

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| SPA-S1 | S | User is phished on a lookalike origin and discloses password and TOTP. | M | H | MFA, HSTS, same-origin SPA, user guidance; no credentials in URLs. | 1 | Phishing tabletop; auth UI review. | Medium |
| SPA-T1 | T | Stored XSS in a master-data field executes in the SPA origin and calls the API with the in-memory JWT. | M | H | React escaping, no `dangerouslySetInnerHTML`, server-side output encoding, strict CSP with nonces/hashes. | 2 | `tests/security/Web/StoredXss.spec.ts`; CSP header assertions. | Medium |
| SPA-I1 | I | Access token is accidentally persisted to `localStorage`, `sessionStorage`, or logs, surviving browser restart. | L | H | Memory-only token; lint/review rule banning storage APIs for auth; no token logging. | 1 | Grep-based unit check plus Playwright storage inspection. | Low |
| SPA-I2 | I | A sibling/subdomain attacker reads the refresh cookie or forces it over HTTP. | L | H | Host-only cookie, `Secure`, `HttpOnly`, `SameSite=Strict`, path `/api/auth`; no wildcard domain. | 1 | Cookie attribute test; subdomain-cookie probe. | Low |
| SPA-D1 | D | Authorized user bulk-exports or scrapes data beyond business need. | M | M | Permissioned exports, row limits, audit of exports, rate limiting. | 6 | `tests/security/Reports/ReportExportAuthzTests.cs`. | Medium |
| SPA-E1 | E | UI hides an admin action but a user invokes the API directly. | H | H | Server-side deny-by-default authorization and object-level checks; UI is never a control. | 1 | `tests/security/Authorization/VerticalAccessTests.cs`. | Low |
| SPA-R1 | R | User denies performing a posting or master-data change. | M | M | Server-generated audit record with actor, before/after, IP, UA, UTC, correlation ID. | 1 | `tests/security/Audit/AuditTamperTests.cs`. | Low |

### 5.2 Edge / nginx + TLS

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| EDGE-S1 | S | Wrong certificate, SNI mismatch, or expired cert trains users to bypass warnings. | L | H | Automated certificate expiry monitoring, correct SNI, HSTS only after TLS is proven. | 7 | External TLS scan; cert-expiry alert test. | Low |
| EDGE-T1 | T | Request smuggling via conflicting `Content-Length`/`Transfer-Encoding` handling between nginx and Kestrel. | L | H | Reject ambiguous framing, consistent header limits, current nginx/Kestrel, no HTTP/1.0 upgrades. | 0 | Smuggling probes against compose stack. | Low |
| EDGE-I1 | I | Proxy or browser caches authenticated API responses containing PII or financial data. | M | H | API sends `Cache-Control: no-store`; nginx disables caching for `/api`; no shared cache. | 0 | Header assertions on authenticated routes; nginx config test. | Low |
| EDGE-I2 | I | Path traversal or alias misconfiguration exposes files outside the SPA root. | L | H | Exact `location` blocks, no user-controlled alias, deny dotfiles, SPA fallback only for known routes. | 0 | nginx config test and traversal probes. | Low |
| EDGE-D1 | D | Volumetric or slow HTTP flood exhausts nginx, API, or database connections. | M | H | Edge connection/rate limits, API global rate limiting, timeouts, DB connection pool caps. | 1 | Load test and 429/503 behavior test. | Medium |
| EDGE-E1 | E | Client spoofs `X-Forwarded-For` to bypass IP rate limits or poison audit IPs. | M | H | `ForwardedHeaders` restricted to known proxies/networks; overwrite untrusted values; test topology. | 1 | `tests/security/RateLimiting/ForwardedHeaderSpoofTests.cs`. | High |
| EDGE-T2 | T | Weak TLS versions/ciphers or HTTP still reachable after misconfiguration. | M | H | TLS 1.2+ only, modern cipher suite, HTTP-to-HTTPS redirect, HSTS at the terminator. | 7 | TLS scanner; redirect test. | Low |
| EDGE-S2 | S | Host-header injection poisons absolute links or password-reset URLs. | L | M | `AllowedHosts`, host validation, configure public base URL explicitly; no user-supplied host in links. | 1 | Host-header fuzz test on auth endpoints. | Low |

### 5.3 API gateway / middleware

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| API-S1 | S | Attacker supplies a forged correlation ID to confuse investigation or inject log content. | M | L | `X-Correlation-ID` restricted to 64 ASCII alphanumerics/`-_.`; invalid values replaced. Implemented. | 0 | `CorrelationIdTests` and integration tests. | Low |
| API-T1 | T | Overposting binds client fields such as totals, permissions, or audit columns. | M | H | DTOs only, never bind EF entities; server recomputes totals and server-owned fields. | 2 | `tests/security/Input/MassAssignmentTests.cs`. | Low |
| API-T2 | T | Oversized or compressed request body exhausts memory or CPU. | M | M | Kestrel 10 MiB cap, per-endpoint limits, nginx `client_max_body_size`, no unbounded decompression. | 1 | Boundary tests at and above limits. | Medium |
| API-I1 | I | Exception details or SQL errors disclose schema, paths, or stack traces. | M | H | Problem details with correlation ID only; no developer exception page outside Development; sanitize logs. | 1 | Forced-error integration tests in Production environment. | Low |
| API-I2 | I | CORS policy permits an attacker origin to read responses or drive cookie endpoints. | M | M | Fail-closed origin allow-list; explicit methods/headers; credentials only for approved origins. Current policy is broad on headers/methods (**M-01, Medium**). | 1 | CORS preflight matrix; malicious-origin test. | Medium |
| API-D1 | D | Login, refresh, search, or export endpoints are flooded. | H | M | Global and per-endpoint rate limits, request timeouts, pagination max 100, query timeouts. | 1 | `tests/security/RateLimiting/*`; load test. | Medium |
| API-E1 | E | A new endpoint is added without authorization and is anonymously reachable. | M | H | Deny-by-default fallback policy; every endpoint declares a permission; startup test fails on unnamed policies. | 1 | Endpoint authorization matrix test. | Low |
| API-R1 | R | Sensitive mutation succeeds but no attributable request/audit record exists. | M | H | Audit in the application transaction for privileged/financial actions; correlation ID in every record. | 1 | Audit completeness test per mutation. | Medium |

### 5.4 Identity / authentication

MFA is mandatory for Admin and Finance roles; local ASP.NET Identity remains the v1 assumption pending the IdP decision in Section 12.

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| ID-S1 | S | Credential stuffing or password guessing against login. | H | H | Min length 12, PBKDF2 Identity hasher, lockout, per-IP and per-account rate limits, breached-password check where feasible. | 1 | `tests/security/Authentication/LockoutTests.cs`. | Medium |
| ID-S2 | S | Username enumeration from different errors, status codes, or timing. | M | M | Uniform failure response, constant-time verification, rate limiting, no "user exists" messages. | 1 | Timing and response-differential test. | Low |
| ID-T1 | T | JWT `alg=none`, algorithm confusion, or a token signed with the wrong key type is accepted. | L | H | Pin the ADR-0002 algorithm, validate issuer, audience, lifetime, key, and signature; reject `none`; use the framework JWT handler. | 1 | `tests/security/Authentication/JwtValidationTests.cs`. | Low |
| ID-T2 | T | JWT signing key leaks through repo, logs, image, or environment dump. | M | H | Secret manager, gitleaks, no key in images, rotation with overlap, restart runbook. | 1 | Secret scan; key-rotation drill. | Medium |
| ID-S3 | S | Replayed TOTP code within its time window. | M | H | Reject a used time step per user, limit attempts, require fresh login flow; store TOTP secret encrypted. | 1 | `tests/security/Authentication/TotpTests.cs`. | Low |
| ID-T3 | T | Stolen refresh token is replayed; rotation is not enforced. | M | H | Rotate every use, store only a hash, detect reuse, revoke the whole token family, revoke on logout/password/role change. | 1 | `tests/security/Authentication/RefreshReuseTests.cs`. | Low |
| ID-E1 | E | MFA enrollment is bypassed or an attacker enrolls their own TOTP device. | L | H | Require current password plus authenticated session, confirm a valid code before activation, audit enrollment, no admin-side secret retrieval. | 1 | Enrollment abuse test. | Low |
| ID-I1 | I | Password-reset or invitation token leaks or is reused. | L | H | Single-use, short TTL, stored hashed, no token in logs/URLs where avoidable, invalidate on password change. | 1 | Reset-flow token reuse test. | Low |
| ID-D1 | D | Lockout is weaponised to deny service to known users. | M | M | Combine progressive delays with IP/account rate limits, alerting, and admin unlock; do not reveal lockout state publicly. | 1 | Lockout DoS test with monitoring assertion. | Medium |
| ID-T4 | T | CSRF drives refresh/logout with the victim's cookie. | M | H | `SameSite=Strict`, Origin allow-list, custom `X-Requested-With` header, same-origin nginx; no state change from GET. | 1 | `tests/security/Authentication/CookieCsrfTests.cs`. | Low |

### 5.5 Authorization / business rules

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| AZ-E1 | E | IDOR: a clerk changes an object ID and reads another user's or another scope's record. | H | H | Object-level authorization on every read/write; scope from server-side identity, never request body. | 1 | `tests/security/Authorization/IdorTests.cs` across all endpoints. | Low |
| AZ-E2 | E | Horizontal escalation by changing customer, warehouse, or owner IDs in a request. | H | H | Authorize the target object and relationships, not just the route; deny by default. | 2 | `HorizontalAccessTests.cs`. | Low |
| AZ-E3 | E | Vertical escalation by adding a role/permission claim client-side or calling an admin route. | M | H | Signed JWT, permission claims validated server-side, deny-by-default fallback, no client-trusted roles. | 1 | `VerticalAccessTests.cs`. | Low |
| AZ-E4 | E | Separation-of-duties bypass: PO creator approves own PO, or invoice poster reverses own posting. | M | H | Compare actor ID to creator/poster; require distinct permission and, where configured, a second approver. | 4 | `SeparationOfDutiesTests.cs` (PO Phase 4, invoice Phase 5). | Low |
| AZ-T1 | T | Stale permission claims persist after role removal. | M | M | 15-minute access tokens, revoke refresh families on role/permission change, re-evaluate permissions on refresh. | 1 | Role-change propagation test with <=15 min bound. | Medium |
| AZ-T2 | T | Soft-deleted record remains accessible by direct ID or appears in reports. | M | M | Global query filters, filtered unique indexes, explicit tombstone handling, object checks. | 2 | Soft-delete access test. | Low |
| AZ-E5 | E | Forced browsing to report exports or admin endpoints bypasses menu permissions. | M | H | Permission per endpoint, report row scope, export authorization re-check server-side. | 1 | `tests/security/Reports/ReportExportAuthzTests.cs`. | Low |
| AZ-I1 | I | 403/404 differences reveal whether a record exists. | M | L | Return 404 for unauthorized object access where appropriate; consistent problem details. | 1 | Response-differential test. | Low |
| AZ-R1 | R | Privileged action is performed but the actor disputes it. | M | H | Audit every authorization decision for privileged/financial actions with actor and target. | 1 | Audit completeness test. | Low |

### 5.6 Application / Domain logic

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| APP-T1 | T | Illegal state transition, double posting, or posting a reversed invoice again. | M | H | Explicit state machine, domain invariants, DB constraints, idempotency, period locks. | 4 | State-machine and illegal-transition tests. | Low |
| APP-T2 | T | Two concurrent sales consume the last unit, creating negative stock. | M | H | Transactions plus optimistic concurrency/rowversion; appropriate isolation; reservation rules; CHECK constraints. | 3 | `NegativeStockConcurrencyTests.cs` with two parallel requests. | Low |
| APP-T3 | T | Journal entry posts with debits not equal to credits. | M | H | Enforce in domain, application transaction, and database constraint/trigger; reject unbalanced batches. | 5 | `JournalBalanceTests.cs` and property-based trial-balance test. | Low |
| APP-T4 | T | Floating-point conversion changes money or quantities. | M | H | `decimal` end-to-end, `DECIMAL(19,4)`/`DECIMAL(18,4)`, JSON strings, no `double`/`float`. | 2 | Round-trip tests and schema assertions. | Low |
| APP-T5 | T | Idempotency key is reused with a different payload, duplicating or corrupting a posting. | M | H | Store key + actor + endpoint + request hash + result; same key/different payload -> conflict; replay stored result. | 5 | `IdempotencyTests.cs`. | Low |
| APP-T6 | T | Client tampers with prices, totals, tax, or stock quantities in the request. | H | H | Recalculate from server-side data, validate ranges, ignore client-owned totals; DTO allow-list. | 4 | Price/total tampering tests. | Low |
| APP-I1 | I | Cost, margin, bank, or tax data leaks to roles without need. | M | H | Field-level projection/masking, permission checks, report column scoping. | 2 | Role-by-field response test. | Medium |
| APP-D1 | D | Expensive search, sort, or export query exhausts the database. | M | M | Whitelisted sort/filter fields, indexes, max page size 100, query timeout, export row cap. | 2 | Query-plan review and load test. | Medium |
| APP-T7 | T | CSV export cells beginning with `=`, `+`, `-`, or `@` execute formulas in Excel. | M | M | Neutralise dangerous prefixes, quote fields, document export behavior, test generated files. | 6 | `CsvInjectionTests.cs`. | Low |
| APP-T8 | T | Reservation race oversells stock between order confirmation and shipment. | M | H | Atomic reservation transaction, rowversion, revalidation at shipment, compensating release on cancel. | 4 | Concurrency test for confirm/ship race. | Low |

### 5.7 SQL Server / data at rest

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| DB-S1 | S | API runtime login is `sa`, `db_owner`, or has DDL rights. | M | H | Separate migration and runtime logins; runtime has explicit SELECT/INSERT/UPDATE only; no DDL. | 1 | Login/permission assertions in integration tests. | Low |
| DB-T1 | T | SQL injection through raw concatenation in search, sort, or report filters. | M | H | EF Core parameterization only; no string-built SQL; CodeQL; review rule. | 2 | `SqlInjectionTests.cs` plus SAST. | Low |
| DB-T2 | T | Application or operator updates/deletes audit or ledger rows to hide activity. | M | H | `DENY UPDATE/DELETE` for runtime login on append-only tables; hash chain; separate audit-read permission. | 1 | `AuditTamperTests.cs` attempts direct DML. | Medium |
| DB-I1 | I | Stolen database backup or media exposes PII, bank details, and financial history. | M | H | Encrypted backups, TDE and/or column encryption, key custody, access control, encrypted offsite copy. | 7 | Backup restore + encryption verification. | Medium |
| DB-I2 | I | DBA or backup operator reads tax IDs/bank details in cleartext. | M | H | Encryption at rest strategy pending; column-level encryption for bank/tax data, masking in UI/logs, least privilege. | 1 | Decryption-permission and masking tests. | Medium |
| DB-T3 | T | Destructive or malicious migration drops data or weakens constraints. | L | H | Forward-only reviewed migrations, migration login only, CI Testcontainers, backup before deploy, schema diff review. | 1 | Migration dry-run and data-integrity tests. | Low |
| DB-T4 | T | Lost update because rowversion/concurrency token is ignored on update. | M | M | `RowVersion` on every business aggregate; reject stale writes with 409; integration tests. | 2 | Concurrent update test. | Low |
| DB-D1 | D | Long transactions or lock contention block postings and reports. | M | M | Short transactions, indexes, query timeouts, deadlock retry policy, monitoring. | 5 | Load and deadlock tests. | Medium |
| DB-S2 | S | SQL Server is reachable from untrusted networks. | L | H | Private Docker network; no public DB port in production; firewall allow-list; TLS to DB where supported. | 7 | Network policy and port scan. | Low |

### 5.8 Audit / logging

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| AUD-T1 | T | Audit rows are altered or deleted by an application bug or privileged operator. | M | H | Append-only table, `DENY UPDATE/DELETE`, SHA-256 hash chain over previous hash + canonical payload, external shipping. | 1 | `AuditTamperTests.cs`; chain-verification job test. | Medium |
| AUD-R1 | R | Business action commits but its audit record is missing or silently dropped. | M | H | Audit in the same transaction for critical actions; fail closed on audit failure; outbox for external sink. | 1 | Fault-injection test that audit failure rolls back. | Low |
| AUD-I1 | I | Passwords, tokens, cookies, TOTP codes, PII, or full request bodies appear in logs. | M | H | Structured logging with redaction; no body/header logging; deny-list tests; review. | 0 | Log-capture test that scans for canary secrets. | Medium |
| AUD-I2 | I | Unauthorized staff read the audit trail to learn investigation status or PII. | M | M | `audit.read` permission, least privilege, masked before/after fields. | 1 | Authorization test on audit endpoints. | Low |
| AUD-D1 | D | Log flooding or missing retention fills disk or destroys evidence. | M | M | Rate limits, log levels, retention policy, rotation, central sink, disk alerts. | 1 | Retention and disk-pressure test. | Medium |
| AUD-T2 | T | Client-supplied correlation ID is treated as a trusted event identifier. | M | L | Keep a server request ID distinct from the client correlation ID; correlation is for tracing, not identity. | 0 | Log schema review. | Low |
| AUD-R2 | R | Clock skew or local-time timestamps make chronology unreliable. | M | M | UTC timestamps from a single source; NTP; store offset-independent `DateTimeOffset`/UTC. | 1 | Timestamp-format test. | Low |

### 5.9 CI/CD and supply chain

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| CI-S1 | S | Typosquatted or compromised npm/NuGet package executes in build or runtime. | M | H | Lockfiles, `npm ci`, NuGet lock mode, pinned versions, dependency review, Security approval for new deps. | 0 | Dependency audit and lockfile diff gate. | Medium |
| CI-T1 | T | Workflow injection via PR title, branch name, issue body, or commit message interpolated into `run`. | M | H | No untrusted context in shell; use env variables and quoted args; least-privilege `GITHUB_TOKEN`. | 0 | Workflow review and actionlint. | Low |
| CI-T2 | T | Build artifact or image is replaced between build and deploy. | L | H | Immutable digests, signed images/provenance, deploy by digest, restricted registry write access. | 7 | Signature/provenance verification in deploy. | Medium |
| CI-I1 | I | Secrets leak in CI logs, test artifacts, or caches. | M | H | gitleaks, masking, OIDC to registry/cloud, no long-lived secrets, artifact retention limits. | 0 | Secret scan and artifact inspection. | Low |
| CI-E1 | E | Over-privileged pipeline can push to `main` or deploy production without review. | M | H | Branch protection, required reviews, environment approvals, least-privilege tokens, no self-approval. | 0 | Branch-protection and environment-policy audit. | Low |
| CI-T3 | T | Vulnerable or malicious base image or OS package ships to production. | M | H | Minimal non-root images, digest pinning, Trivy fs+image, rebuild cadence, SBOM. | 0 | Trivy gate and image inspection. | Medium |
| CI-D1 | D | CI outage or flaky scanners block releases and encourage bypass. | M | L | Required checks, retry policy, documented emergency exception with human approval. | 7 | Pipeline runbook test. | Low |

### 5.10 Backup / restore and operations

| ID | Cat | Scenario | L | I | Planned mitigation | Phase | Verification / test | Residual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| OPS-I1 | I | Unencrypted backup is stolen from storage or transit. | M | H | Encrypted backup media, TLS transfer, access-controlled bucket/share, key custody. | 7 | Backup-at-rest inspection and restore test. | Medium |
| OPS-T1 | T | Restore uses a corrupt or tampered backup, or silently loses ledger/audit data. | L | H | Checksums, restore into isolated environment, ledger/audit chain verification, documented drill. | 7 | Full restore drill with reconciliation. | Medium |
| OPS-S1 | S | Backup operator credentials are compromised or shared. | M | H | Named accounts, MFA, least privilege, separate backup role, audit, no shared passwords. | 7 | Access review and credential test. | Medium |
| OPS-D1 | D | Ransomware or deletion destroys primary and backup copies. | M | H | 3-2-1 copies, immutability/object lock, offline copy, retention, restore runbook. | 7 | Immutability and restore test. | Medium |
| OPS-I2 | I | Production secrets are stored in compose files, images, or environment dumps. | M | H | Secret manager in production, `.env.example` only in repo, no secrets in images, rotation. | 7 | Image/env inspection. | Medium |
| OPS-T2 | T | Audit/log retention is too short for financial or incident investigation. | M | M | Retention policy aligned with legal requirements; central immutable sink; documented deletion. | 7 | Retention configuration review. | Medium |
| OPS-E1 | E | A DBA or operator changes data or permissions outside the application and bypasses SoD. | L | H | Just-in-time access, change tickets, DB audit, external audit sink, separation of duties. | 7 | Privileged-access review. | Medium |

**Findings to acknowledge at the Phase 0 gate (Medium unless marked High):** M-01 broad CORS headers/methods (API edge, Medium); M-02 no trusted-proxy configuration yet (Medium); M-03 no rate limiting yet (Medium); M-04 no audit trail yet (Medium); M-05 no encryption-at-rest decision (**High**); M-06 no backup encryption/restore drill (**High**); M-07 no MFA yet (**High**). Each is acceptable only for the Phase 0 skeleton and must be closed or formally excepted by its target phase.

## 6. Top risks ranked

| Rank | Risk | Severity | Owner | Target phase | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | Broken object-level authorization/IDOR across business records | Critical | Backend Agent | 1 (framework), 2-6 (per module) | Open - planned |
| 2 | JWT signing key compromise or algorithm confusion enables impersonation | High | Backend Agent / DevOps | 1 | Open - planned |
| 3 | Refresh-token theft or reuse without family revocation | High | Backend Agent | 1 | Open - planned |
| 4 | Audit/ledger tampering by over-privileged application login | High | DB Agent / Backend | 1 | Open - planned |
| 5 | Financial logic bypass: unbalanced journal, double posting, SoD violation | High | Backend Agent / DB Agent | 4-5 | Open - planned |
| 6 | Stored XSS in master data leading to token theft and data exfiltration | High | Frontend Agent / Backend | 2 | Open - planned |
| 7 | PII, tax IDs, and bank details exposed at rest or to the wrong role | High | Architect / DB Agent | 1-2 | Open - decision needed |
| 8 | Negative stock/oversell under concurrency | High | Backend Agent / DB Agent | 3 | Open - planned |
| 9 | Supply-chain compromise via dependency, workflow, or container image | High | DevOps Agent | 0/7 | Open - CI gates planned |
| 10 | CSRF or cookie theft on refresh/logout endpoints | High | Backend Agent | 1 | Open - planned |
| 11 | Backup theft or unrecoverable data after ransomware | High | DevOps Agent | 7 | Open - planned |
| 12 | Login brute force and rate-limit bypass via spoofed forwarded headers | High | Backend Agent / DevOps | 1 | Open - **M-02/M-03** Phase 0 exceptions |
| 13 | CSV formula injection in exports | Medium | Backend Agent | 6 | Open - planned |
| 14 | CORS header/method breadth on cookie-capable API | Medium | Backend Agent | 1 | Open - **M-01** |

## 7. Abuse-case / security test plan

Files are future locations under `tests/security` unless stated. None of these tests exist in Phase 0.

| Test ID | Attack | Expected control | Phase | File |
| :--- | :--- | :--- | :--- | :--- |
| SEC-AUTHZ-001 | Change object ID to read/update another record (IDOR) | Object-level authorization returns 403/404; no data leak | 1-2 | `tests/security/Authorization/IdorTests.cs` |
| SEC-AUTHZ-002 | Horizontal escalation via customer/warehouse/owner ID | Relationship and target-object checks | 2 | `tests/security/Authorization/HorizontalAccessTests.cs` |
| SEC-AUTHZ-003 | Vertical escalation: clerk calls admin/finance endpoints | Deny-by-default permission policy | 1 | `tests/security/Authorization/VerticalAccessTests.cs` |
| SEC-AUTHZ-004 | Forced browsing to an endpoint with no declared policy | Fallback policy denies; startup matrix complete | 1 | `tests/security/Authorization/DefaultDenyTests.cs` |
| SEC-AUTHZ-005 | PO creator approves own PO; poster reverses own invoice | Separation-of-duties check | 4-5 | `tests/security/Authorization/SeparationOfDutiesTests.cs` |
| SEC-AUTHZ-006 | Report export for an unauthorized scope or oversized row set | Export permission, row scope, row cap | 6 | `tests/security/Reports/ReportExportAuthzTests.cs` |
| SEC-JWT-001 | `alg=none`, algorithm confusion, wrong issuer/audience/key | Pinned algorithm and full token validation | 1 | `tests/security/Authentication/JwtValidationTests.cs` |
| SEC-JWT-002 | Replay expired or revoked access token | Lifetime and revocation checks | 1 | `tests/security/Authentication/TokenReplayTests.cs` |
| SEC-REFRESH-001 | Reuse a rotated refresh token | Reuse detection and token-family revocation | 1 | `tests/security/Authentication/RefreshReuseTests.cs` |
| SEC-CSRF-001 | Cross-site POST to refresh/logout without Origin or custom header | SameSite=Strict plus Origin allow-list plus `X-Requested-With` | 1 | `tests/security/Authentication/CookieCsrfTests.cs` |
| SEC-AUTH-002 | Password spray and lockout bypass across accounts/IPs | Per-account and per-IP limits, lockout, alerting | 1 | `tests/security/Authentication/LockoutTests.cs` |
| SEC-RATE-001 | Spoof `X-Forwarded-For` to evade IP rate limits | Trusted-proxy allow-list and overwrite semantics | 1 | `tests/security/RateLimiting/ForwardedHeaderSpoofTests.cs` |
| SEC-MFA-001 | Replay TOTP or enroll attacker device | Time-step replay rejection; re-auth before enrollment | 1 | `tests/security/Authentication/TotpTests.cs` |
| SEC-INPUT-001 | Mass assignment of totals, role, owner, audit fields | DTO allow-list; server-owned fields ignored/rejected | 2 | `tests/security/Input/MassAssignmentTests.cs` |
| SEC-INPUT-002 | SQL injection in search/sort/filter values | EF parameterization; sort/filter allow-list | 2 | `tests/security/Input/SqlInjectionTests.cs` |
| SEC-XSS-001 | Stored XSS in customer/item/notes fields | Output encoding; no raw HTML; CSP blocks inline script | 2 | `tests/security/Web/StoredXss.spec.ts` |
| SEC-EXPORT-001 | CSV cells beginning with `=`, `+`, `-`, `@` | Formula neutralisation and safe quoting | 6 | `tests/security/Reports/CsvInjectionTests.cs` |
| SEC-IDEMP-001 | Replay `Idempotency-Key` with same and different payloads | Same payload replays result; different payload conflicts | 5 | `tests/security/BusinessLogic/IdempotencyTests.cs` |
| SEC-BL-001 | Two concurrent sales of the last unit | Transaction plus rowversion/constraint prevents negative stock | 3 | `tests/security/BusinessLogic/NegativeStockConcurrencyTests.cs` |
| SEC-BL-002 | Post an unbalanced journal or tamper with posted lines | Code and DB reject imbalance; posted entries immutable | 5 | `tests/security/BusinessLogic/JournalBalanceTests.cs` |
| SEC-AUDIT-001 | Direct UPDATE/DELETE on audit or ledger rows | Runtime login denied; hash chain detects tampering | 1 | `tests/security/Audit/AuditTamperTests.cs` |
| SEC-SSRF-001 | Inject a URL into a report/export parameter to force server fetch | No server-side URL fetch in v1; PDF renderer sandboxed if added | 6-7 | `tests/security/Input/SsrfTests.cs` |
| SEC-SC-001 | Vulnerable dependency or container image reaches main | Lockfiles, audit, CodeQL, Trivy, gitleaks gates block merge | 0 | `.github/workflows/ci.yml` |

## 8. ASVS Level 2 mapping summary

Chapter mapping uses ASVS 4.0.3 for traceability. If the human gate selects ASVS 5.0, the mapping must be re-baselined before Phase 1.

| ASVS chapter | Status | Phase / note |
| :--- | :--- | :--- |
| V1 Architecture, Design, Threat Modeling | Partial | Phase 0: this model; full review at Phase 7. |
| V2 Authentication | Planned | Phase 1: Identity, password policy, lockout, MFA. |
| V3 Session Management | Planned | Phase 1: JWT lifetime, refresh rotation, replay detection, logout. |
| V4 Access Control | Planned | Phase 1 framework; object-level checks Phase 2-6. |
| V5 Validation, Sanitization, Encoding | Partial | Phase 0 headers; server validation and UI encoding Phase 2. |
| V6 Stored Cryptography | Planned | Phase 1 token/key handling; encryption-at-rest decision Phase 1-2. |
| V7 Error Handling and Logging | Partial | Phase 0 problem details/correlation; audit Phase 1. |
| V8 Data Protection | Planned | Phase 1-2: PII/tax/bank classification, masking, encryption. |
| V9 Communication | Partial | Phase 0 headers/HSTS code; nginx TLS and proxy trust Phase 0/7. |
| V10 Malicious Code | Planned | Phase 0 CI scans; image hardening and signing Phase 7. |
| V11 Business Logic | Planned | Phase 3-5: stock, state machines, ledger, idempotency, SoD. |
| V12 Files and Resources | Partial | No uploads in v1; export controls Phase 6. |
| V13 API and Web Service | Partial | Phase 0 health API; OpenAPI, auth, schema validation Phase 1-2. |
| V14 Configuration | Partial | Phase 0 fail-closed CORS and `.env.example`; secrets management Phase 7. |

OWASP Top 10 (2021) coverage:

| Category | Coverage | Primary controls / phase |
| :--- | :--- | :--- |
| A01 Broken Access Control | Planned | Deny-by-default, object-level checks, SoD; Phase 1-6 |
| A02 Cryptographic Failures | Partial | TLS planned, encryption-at-rest decision open; Phase 1-7 |
| A03 Injection | Planned | EF only, validation, encoding, CSP; Phase 1-2 |
| A04 Insecure Design | Partial | Threat model, state machines, concurrency, idempotency; Phase 0-5 |
| A05 Security Misconfiguration | Partial | Headers, fail-closed CORS, non-root images, no Swagger in prod; Phase 0/7 |
| A06 Vulnerable and Outdated Components | Planned | Lockfiles, audits, Trivy, CodeQL; Phase 0 |
| A07 Identification and Authentication Failures | Planned | Identity, MFA, lockout, refresh rotation; Phase 1 |
| A08 Software and Data Integrity Failures | Partial | CI gates now; artifact signing and audit hash chain Phase 1/7 |
| A09 Security Logging and Monitoring Failures | Planned | Structured logs, audit, alerts; Phase 1/7 |
| A10 Server-Side Request Forgery | Not applicable in v1 | No server-side outbound fetch; revisit if PDF/URL import is added |

## 9. Logging, monitoring, and detection requirements

Must log (structured, UTC, with correlation ID and actor where known): authentication success/failure, lockout, MFA enrollment/verification failure, refresh-token reuse, authorization denials, role/permission changes, master-data changes, document posting/reversal, stock adjustments, journal posting, period close, audit-chain verification failure, migration execution, backup/restore outcome, and security-scan failures.

Detection requirements (target Phase 1, refine Phase 7):

| Signal | Proposed threshold | Action |
| :--- | :--- | :--- |
| Repeated login failures | 5 per account or 20 per IP in 5 minutes | Alert; lockout/rate limit; investigate source |
| Refresh-token reuse | Any occurrence | Revoke token family; alert security |
| Authorization denials | Spike or repeated object-ID probing | Alert; correlate actor/IP |
| Audit chain mismatch | Any occurrence | Page on-call; freeze privileged changes; preserve evidence |
| Privileged data change outside app hours | Any off-hours admin grant or manual DB change | Alert and require ticket reference |
| Export volume | Above configured per-user/day cap | Alert; review permission and business need |
| Dependency/container critical finding | Any | Block merge/release; remediate or human exception |

Never log: passwords, password hashes, TOTP secrets or codes, JWT access tokens, refresh tokens, cookies, `Authorization` headers, full request/response bodies, connection strings, signing keys, encryption keys, full tax IDs, full bank account details, or unredacted PII. Audit `before/after` JSON must mask sensitive fields before persistence.

## 10. Residual risk register and Phase 0 accepted risks

| ID | Residual risk | Severity | Phase 0 disposition | Owner / expiry |
| :--- | :--- | :--- | :--- | :--- |
| RR-01 | `/health` and `/healthz` are anonymous and return only status/timestamp (no dependency details). | Low | Accepted; required for liveness/readiness. | DevOps; re-review if payload grows |
| RR-02 | Swagger UI is Development-only but could be exposed by a misconfigured environment. | Medium | Accepted with deployment check; never enable in Production. | DevOps; Phase 1 |
| RR-03 | No authentication yet; only health routes exist, no business data endpoints. | Medium | Accepted only because no business endpoints exist; do not merge any business endpoint before Phase 1 auth. | Backend; closes Phase 1 |
| RR-04 | Docker/dev secrets are placeholders in `.env.example`; developers may reuse weak values. | Medium | Accepted for local dev only; `.env` ignored, gitleaks on, rotate and never reuse in shared environments. | DevOps; Phase 0/7 |
| RR-05 | No trusted-proxy configuration yet; the API does not yet consume forwarded headers. | Medium | **M-02**: accepted for Phase 0; client-IP controls are not reliable until KnownProxies/KnownNetworks and `ForwardLimit` are configured and tested. | DevOps; Phase 1 |
| RR-06 | No MFA yet. | High | Accepted for Phase 0; mandatory for Admin/Finance before those endpoints ship. | Backend; Phase 1 |
| RR-07 | No rate limiting or lockout yet. | Medium | **M-03**: accepted for Phase 0 health-only surface; required before login ships. | Backend; Phase 1 |
| RR-08 | CORS uses `AllowAnyHeader`/`AllowAnyMethod` with a fail-closed origin list. | Medium | **M-01**: accepted for Phase 0 health-only surface; restrict to required methods/headers in Phase 1. | Backend; Phase 1 |
| RR-09 | No audit log or hash chain yet; no business writes exist. | Medium | **M-04**: accepted for Phase 0; audit must ship with Phase 1 identity/admin changes. | Backend / DB; Phase 1 |
| RR-10 | No encryption-at-rest decision for PII, tax IDs, or bank details. | High | **M-05**: open decision before Phase 2 master data; TDE and/or column-level encryption. | Architect; Phase 1 |
| RR-11 | No backup encryption or restore drill yet. | High | **M-06**: accepted for Phase 0 with no production data; required before Phase 7 release. | DevOps; Phase 7 |
| RR-12 | Local development may run without TLS; HSTS/secure cookies differ from production. | Medium | Accepted only on localhost; production must terminate TLS and never disable `Secure` cookies. | DevOps; Phase 0/7 |
| RR-13 | JWT signing key is a placeholder in `.env.example`; rotation process not implemented. | High | Accepted for dev only; production secret manager and rotation runbook required Phase 1. | DevOps; Phase 1 |

## 11. Open questions for the human gate

1. **TLS termination:** Is nginx the TLS terminator, or is there an upstream cloud load balancer? Who owns certificate issuance/renewal, and where is HSTS applied? This fixes whether the API or nginx must emit HSTS.
2. **Key management and rotation:** Where will the JWT signing key live in production (secret manager, KMS, vault)? What is the rotation overlap strategy, and how are old tokens invalidated without mass logout?
3. **Cookie domain strategy:** Will the SPA and API stay same-origin, or use an `api.` subdomain? Should the refresh cookie be host-only with path `/api/auth`, and should we use `__Secure-` (path-scoped) rather than `__Host-` (which requires path `/`)?
4. **Data retention:** How long are audit logs, financial records, PII, and backups retained? What legal/accounting retention applies, and how does soft delete interact with erasure requests?
5. **PII/tax-ID encryption:** Is TDE sufficient, or do tax IDs and bank details require column-level/Always Encrypted protection? Do these fields need searchable indexes, and who can decrypt?
6. **Backup encryption and key custody:** Which backup encryption method and key custodian are approved? Who can restore, where is the offsite/immutable copy, and how often is a restore drill required?
7. **Identity provider:** Confirm local ASP.NET Identity for v1, or select an external OIDC IdP. If external, who owns MFA, lockout, refresh, and account recovery?
8. **Finance approval thresholds:** What PO amount triggers approval, who may approve, and who may post or reverse invoices? Is a second approver required above a threshold, and can admins override SoD?
9. **Trusted proxy topology:** What are the exact proxy IPs/networks and `ForwardLimit`? Should the API trust forwarded headers from nginx only, and how is client IP represented in audit records?
10. **Export/PDF scope:** Will Phase 6 PDF generation use a local renderer or a remote service? If remote or URL-fetching, SSRF and data-egress controls must be added to this model.

## 12. Phase 0 exit checklist (Security Agent)

- [ ] This threat model reviewed and approved at the Phase 0 human gate; open questions answered or explicitly deferred.
- [ ] No open Critical/High finding in Phase 0 scope; Medium findings have an owner, target phase, and acceptance or ADR exception.
- [ ] CI gates present and green: build, unit/Testcontainers, ESLint/tsc, CodeQL, gitleaks, dotnet/npm audit, Trivy fs+image, Spectral, compose config validation.
- [ ] Only `.env.example` is tracked; gitleaks clean; placeholder secrets clearly marked dev-only.
- [ ] `GET /health` and `GET /healthz` are anonymous, return no dependency details or secrets, and are covered by tests.
- [ ] Baseline headers verified: `X-Content-Type-Options`, frame denial, CSP, `Referrer-Policy`, `Cache-Control: no-store`.
- [ ] CORS fail-closed in production configuration; broad header/method policy logged as **M-01** for Phase 1 tightening.
- [ ] Swagger UI unavailable outside Development; production environment configuration cannot enable it accidentally.
- [ ] No business-data endpoints exist before Phase 1 authentication and authorization.
- [ ] Trusted-proxy design recorded; forwarded-header spoofing risk logged as **M-02**.
- [ ] ADRs `0002`-`0007` exist and are consistent with this model, or deviations are documented.
- [ ] Docker Compose validates; containers run non-root; images scanned and pinned before Phase 7.
- [ ] Backup/encryption/restore requirements accepted as Phase 7 deliverables (**M-06**).
- [ ] STRIDE tables, top risks, abuse-case plan, and ASVS mapping reviewed for completeness at Phase 7 hardening.

## 13. References

- `PLAN.md` section 1 (scope and non-goals), section 4 (Phase 0 deliverable), section 5 (data/API rules), section 6 (security requirements), section 7 (Security Agent role), section 8 (release gates), section 9 (human gates).
- `docs/adr/0002-auth-model.md` - ASP.NET Identity, JWT, refresh rotation, MFA, lockout.
- `docs/adr/0003-audit-approach.md` - append-only audit, hash chain, masking, audit permission.
- `docs/adr/0004-money-decimal.md` - `DECIMAL(19,4)` money and `DECIMAL(18,4)` quantities.
- `docs/adr/0005-soft-delete.md` - `IsDeleted`, filtered unique indexes, retention behavior.
- `docs/adr/0006-database-access.md` - migration login versus least-privilege runtime login.
- `docs/adr/0007-api-contract.md` - OpenAPI-first contract, RFC 7807, pagination, idempotency.
- `README.md` - repository layout, Phase 0 endpoints, security ground rules.

## Human review decision

Phase 0 threat model review (version 0.1, 2026-11-12):

- [ ] **APPROVE** - threat model is sufficient for Phase 0; proceed to Phase 1.
- [ ] **APPROVE WITH CHANGES** - approve after the listed changes are applied and re-reviewed.
- [ ] **REJECT** - return to the Security Agent with the reasons below.

Reviewer name: ______________________  Date: ______________

Required changes / conditions:

______________________________________________________________________________

______________________________________________________________________________

______________________________________________________________________________
