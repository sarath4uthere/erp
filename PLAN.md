# Mini-ERP: End-to-End Build Plan for Antigravity (Multi-Agent Loop)

## 1. Scope and decisions (fixed, do not renegotiate)

Product: Mini-ERP for a small distributor/workshop. Modules: Master Data, Inventory, Sales, Purchasing, Invoicing + General Ledger, Reports, Admin/Security.

| Layer | Choice |
| :--- | :--- |
| Database | SQL Server 2022 (Docker for dev). Migrations via EF Core or DbUp, versioned in repo |
| Backend | ASP.NET Core 8 Web API, layered (Api / Application / Domain / Infrastructure) |
| Frontend | React + TypeScript + Vite, server-driven forms/tables |
| Auth | ASP.NET Identity + JWT (short-lived) + refresh tokens, TOTP MFA for admins |
| Tests | xUnit, Testcontainers (real SQL Server), Playwright for E2E |
| CI | GitHub Actions |
| Infra | Docker Compose (dev), deployable to any VM or cloud |

(Swap stack only by editing this table before Phase 0.)

Non-goals for v1: multi-company, multi-currency, manufacturing/BOM, payroll, mobile app.

## 2. Agent roles (subagents)

| Agent | Responsibility | Can touch | Must NOT |
| :--- | :--- | :--- | :--- |
| Manager | Reads plan, creates task list per phase, assigns, tracks loop state in docs/STATUS.md | docs, task board | write feature code |
| Architect | ADRs, schema design, API contracts (OpenAPI first) | docs/, /db/design, openapi.yaml | implement features |
| DB Agent | Migrations, indexes, constraints, seed data, stored procs only where needed | /db, /src/Infrastructure | change API contracts |
| Backend Agent | Domain logic, services, endpoints, validation | /src/Api, /src/Application, /src/Domain | bypass authorization, write raw string SQL |
| Frontend Agent | UI against the OpenAPI contract | /web | call undocumented endpoints |
| QA Agent | Unit, integration, E2E tests, test data | /tests | modify production code (reports bugs instead) |
| Security Agent | Threat model, secure code review, SAST/dependency/secret scans, abuse-case tests | everything read-only + /tests/security | approve its own fixes |
| Reviewer | Independent code review vs. plan and ADRs, final merge verdict | read-only | write code |
| DevOps Agent | Docker, CI, secrets handling, backups, logging | /ops, .github | change app logic |

Rule: the agent that writes code never approves it. Backend/DB/Frontend output is judged by QA + Security + Reviewer.

## 3. The loop (per feature/task)

PLAN -> BUILD -> TEST -> SECURITY -> REVIEW -> (PASS: merge) / (FAIL: back to BUILD)

- **PLAN (Architect):** task spec with acceptance criteria, data model change, API contract, security notes.
- **BUILD (DB, Backend, Frontend):** implement on a feature branch `feat/<phase>-<task>`.
- **TEST (QA):** write/run unit + integration tests. Coverage on business logic >= 80%. All green required.
- **SECURITY (Security):** run checklist in section 6, scans, abuse-case tests. Any High/Critical finding = fail.
- **REVIEW (Reviewer):** compare against spec, ADRs, naming, migrations safety. Verdict: PASS / FAIL with itemized reasons.
- **MERGE** only on PASS from QA + Security + Reviewer, then Manager updates docs/STATUS.md.

### Loop guardrails (important):
- Max 3 build-fix iterations per task. On the 4th failure: stop, write `docs/BLOCKED_<task>.md` explaining the problem, and wait for human input.
- No agent may delete tests, weaken assertions, disable scanners, or lower coverage thresholds to get a pass. That is an automatic FAIL.
- No new dependency without Security Agent approval (license, maintenance, known CVEs) and an ADR line.
- Every task commits small, with a message referencing the task ID.
- Manager keeps `docs/STATUS.md` current: task, owner, iteration count, result.

## 4. Phases and deliverables

### Phase 0: Foundation (HUMAN GATE at end)
- Repo structure, solution layout, Docker Compose (SQL Server + API + web), .editorconfig, .gitignore
- CI pipeline: build, test, lint, SAST, dependency audit, secret scan
- ADRs: stack, auth model, audit approach, money/decimal handling, soft-delete policy
- Threat model (STRIDE) in docs/THREAT_MODEL.md by Security Agent
- Secrets: .env.example only; real secrets never in repo
- **Exit:** CI green on empty skeleton, threat model reviewed by human

### Phase 1: Identity, RBAC, Audit
- Users, roles, permissions (permission-based, not just role names)
- Login, refresh, logout, lockout, password policy, TOTP MFA for Admin role
- Central authorization policy applied by default (deny unless explicitly allowed)
- Audit log: who, what entity, before/after, timestamp, IP, correlation ID (append-only table)
- **Exit:** every endpoint requires auth; automated test proves unauthenticated/unauthorized calls return 401/403

### Phase 2: Master Data
- Customers, suppliers, items (SKU, UoM, tax class), warehouses, tax rates
- Validation, uniqueness constraints, soft delete, search/pagination
- **Exit:** CRUD + audit + permission tests

### Phase 3: Inventory (stock ledger)
- StockMovement table is the source of truth (append-only). Quantity on hand is derived/materialized, never overwritten
- Receipts, issues, transfers, adjustments with reason codes
- Costing: moving average (FIFO as a later ADR)
- Concurrency: transactions + optimistic concurrency (rowversion); test two simultaneous sales of the last unit
- **Exit:** stock can never go negative unless setting allows; ledger reconciles to on-hand in a test

### Phase 4: Purchasing and Sales
- PO: draft -> approved -> received -> closed (approval threshold workflow)
- SO: draft -> confirmed -> picked -> shipped -> invoiced, with stock reservation
- Returns (credit note / return to supplier)
- **Exit:** state machine tests, illegal transitions rejected

### Phase 5: Invoicing and General Ledger
- Chart of accounts, double-entry journal (debits = credits enforced in DB and in code)
- Auto-posting from invoices, receipts, payments, stock movements
- AR/AP, payments allocation, period close (locked periods cannot be edited)
- **Exit:** trial balance always balances in property-based tests

### Phase 6: Reports and Dashboards
- Stock valuation, sales by customer/item, AR/AP aging, trial balance, P&L
- Export CSV/PDF with permission checks and row limits
- **Exit:** report totals reconcile with ledger

### Phase 7: Hardening and Release (HUMAN GATE)
- Full security review, pen-test style abuse suite, dependency/container scan
- Performance test on realistic volumes (100k items, 1M movements)
- Backup/restore drill, runbook, docs/OPERATIONS.md
- **Exit:** all gates in section 8 pass

## 5. Data and API rules (enforced by Architect + Reviewer)
- Money: DECIMAL(19,4), never float. Quantities DECIMAL(18,4).
- Every table: Id, CreatedAt/By, UpdatedAt/By, RowVersion. Soft delete via IsDeleted where business records must persist.
- Foreign keys and CHECK constraints for invariants (e.g. quantity rules, debit=credit).
- OpenAPI contract written before implementation; Frontend codes against it; contract tests in CI.
- Consistent error format (RFC 7807 problem details); never leak stack traces or SQL errors.
- Pagination mandatory on list endpoints (max page size enforced server-side).
- Idempotency keys on create endpoints that post documents (invoices, payments).

## 6. Security requirements (checklist the Security Agent runs every loop)

Standard: OWASP ASVS Level 2 as the target, OWASP Top 10 as the minimum.

### Authentication and sessions
- Passwords hashed with Argon2id or PBKDF2 (Identity default acceptable), min length 12, breached-password check optional
- Account lockout and rate limiting on login, refresh, password reset
- MFA (TOTP) mandatory for Admin/Finance roles
- JWT access token <= 15 min, refresh token rotation with reuse detection, revocation on logout/password change
- Secure, HttpOnly, SameSite cookies if cookies are used; CSRF protection accordingly

### Authorization
- Deny-by-default; every endpoint declares required permission
- Object-level checks (no IDOR): user can only access records they are permitted to
- Separation of duties: creator of a PO cannot approve it; invoice poster cannot reverse own posting
- Authorization tests for every endpoint (allowed, forbidden, anonymous)

### Input and data
- Parameterized queries / EF only. Raw SQL concatenation = automatic FAIL
- Server-side validation on all inputs (length, type, range); output encoding in UI; no dangerouslySetInnerHTML
- File uploads (if any): type allow-list, size limit, random names, stored outside web root, AV scan hook
- Mass-assignment protection: DTOs only, never bind entities directly
- Sensitive columns (tax IDs, bank details) encrypted at rest (column-level or TDE) and masked in logs/UI

### Transport, config, secrets
- HTTPS only, HSTS, secure headers (CSP, X-Content-Type-Options, X-Frame-Options/frame-ancestors, Referrer-Policy)
- CORS restricted to known origins
- Secrets via environment/secret manager; secret scan in CI (gitleaks); pre-commit hook
- DB account for the app is least-privilege (no sa, no DDL rights at runtime; separate migration account)
- Containers run as non-root, minimal base images, image scan (Trivy)

### Logging, audit, resilience
- Structured logs with correlation IDs; no passwords, tokens, or PII in logs
- Audit log append-only, tamper-evident (hash chain optional), separate permission to read
- Global rate limiting and request size limits
- Dependency audit (dotnet list package --vulnerable, npm audit) and SAST (CodeQL/Semgrep) on every PR
- Backups encrypted, restore tested

Severity policy: Critical/High = block merge. Medium = fix within the phase or log an ADR exception approved by the human. Low = backlog.

## 7. Agent prompts (paste into Antigravity)

### Manager
You are the Manager agent. Read PLAN.md fully. For the current phase, create tasks with IDs, acceptance criteria, and owners from section 2. Run the loop in section 3 for each task using subagents. Enforce the loop guardrails strictly. Update docs/STATUS.md after every task. Stop at each HUMAN GATE and summarize what to review. Never write feature code yourself.

### Architect
You are the Architect agent. For task <ID>, produce: schema changes (DDL plan), OpenAPI additions, state machines, edge cases, and security notes. Follow section 5 rules. Write an ADR for any non-trivial decision. Do not implement.

### DB Agent
Implement only the migrations and data-access changes for task <ID>. Use constraints and indexes for every invariant. Migrations must be forward-only, idempotent in CI, and tested against a real SQL Server container. No raw string-built SQL.

### Backend Agent
Implement task <ID> against the OpenAPI contract. Keep business rules in the Application/Domain layers. Every endpoint needs an authorization policy and validation. Write nothing that violates section 6. Make the QA tests pass without editing them.

### Frontend Agent
Implement task <ID> UI strictly from openapi.yaml. Handle loading, empty, error, and forbidden states. Never store tokens in localStorage; follow the auth approach in the ADR. No raw HTML injection.

### QA Agent
Write and run tests for task <ID>: unit, integration (Testcontainers), and E2E for the main flow. Include concurrency and negative cases. Report failures to the owning agent with reproduction steps. Never modify production code and never weaken a test.

### Security Agent
Review task <ID> against section 6 and docs/THREAT_MODEL.md. Run SAST, dependency, secret, and container scans. Write abuse-case tests (IDOR, privilege escalation, injection, replay, rate-limit bypass) under /tests/security. Output a verdict PASS/FAIL with findings by severity. You cannot fix and approve the same issue.

### Reviewer
Independently review the diff for task <ID> against the spec, ADRs, and section 5. Check migrations for data-loss risk, naming, dead code, and missing tests. Output PASS or FAIL with a numbered list of required changes.

### DevOps Agent
Maintain Docker, CI, and secret handling. CI must run build, tests, SAST, dependency audit, secret scan, and image scan on every PR and block merge on failure. Never store secrets in the repo.

## 8. Definition of Done (per task) and release gates

### Task done when:
- Acceptance criteria met, tests green, coverage threshold held
- Security verdict PASS, Reviewer verdict PASS
- OpenAPI, ADRs, and STATUS.md updated
- No TODOs without a ticket

### Release gates (Phase 7):
- All phases complete, CI green
- Zero open Critical/High findings
- Trial balance and stock ledger reconciliation tests pass
- Authorization test matrix covers 100% of endpoints
- Backup + restore drill completed and documented
- Human sign-off on threat model and operations runbook

## 9. Human gates (you stay in control)

You review and approve at: end of Phase 0 (stack, threat model), Phase 1 (auth design), Phase 5 (accounting correctness, ideally with an accountant), and Phase 7 (release). Any BLOCKED_*.md file also needs your decision.

## 10. Starting steps
1. Create an empty repo, add this file as PLAN.md.
2. Open it in Antigravity, start the Manager agent with the prompt in section 7.
3. Tell it: "Begin Phase 0."
4. Review at each gate, answer blocked items, then say "Proceed to the next phase."
