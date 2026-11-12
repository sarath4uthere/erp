# Security Policy

Mini-ERP handles customer, supplier, inventory, purchasing, sales, and financial data.
Security defects are treated as release blockers under the gate rules in
[`PLAN.md`](../PLAN.md) section 8. This document covers vulnerability reporting, the
security baseline, and the rules contributors must follow.

## Supported versions

The project is pre-release. Only the `main` branch and the latest tagged pre-release are
supported. No production support window exists yet.

| Version | Supported |
| :--- | :--- |
| `main` (pre-release) | Yes |
| Older branches/tags | No |

## Reporting a vulnerability

**Do not open a public issue, pull request, or discussion for a suspected vulnerability.**

Use GitHub private vulnerability reporting (Security > Advisories > Report a
vulnerability) when the repository is hosted on GitHub.

If private reporting is unavailable, contact the security owner through the private
channel recorded in the project's release record.

> Placeholder: the named security contact and monitored mailbox must be set before the
> first release. Tracked as `P7-SEC-01` in [`docs/STATUS.md`](./STATUS.md). Until then,
> do not deploy this project to a production environment.

Include as much of the following as possible:

- affected version, commit, or branch;
- endpoint, screen, or component;
- reproduction steps or a minimal proof of concept;
- impact assessment (confidentiality, integrity, availability, financial effect);
- whether the issue is already public;
- a safe way to contact you and credit preference.

Do not include live production secrets or personal data. Redact tokens, passwords, tax
IDs, bank details, and customer records.

## Response process

1. Acknowledge the report privately.
2. Triage severity using CVSS plus business impact. Any confirmed Critical or High finding
   blocks merge and release.
3. Reproduce in a controlled environment with synthetic data.
4. Fix on a private branch, add a regression/abuse test, and run the full gate.
5. Coordinate disclosure with the reporter after a fix is available.
6. Record the finding, decision, and follow-up in the threat model and `docs/STATUS.md`.

Response and disclosure timelines are best-effort until a production support commitment
exists. They must be defined before release (`P7-SEC-01`).

## Safe harbour

Good-faith research that stays within the rules below will not be pursued or reported.
Do not:

- access, modify, or exfiltrate data that is not yours;
- degrade availability, run destructive tests, or use production credentials;
- test against a live customer environment;
- use social engineering, physical access, or third-party services;
- publish details before coordinated disclosure.

Stop and report immediately if you encounter personal data, credentials, or financial
records.

## Security baseline

The target standard is **OWASP ASVS Level 2**, with OWASP Top 10 as the minimum. The
current threat model is [`docs/THREAT_MODEL.md`](./THREAT_MODEL.md). Architecture decisions
are in [`docs/adr/`](./adr/).

### Authentication and sessions (Phase 1+)

- ASP.NET Identity with a short-lived JWT held in SPA memory only; no tokens in
  `localStorage` or `sessionStorage`.
- Opaque, rotating refresh token in an `HttpOnly`, `Secure`, `SameSite=Strict` cookie
  scoped to `/api/auth`; reuse detection revokes the token family.
- TOTP MFA is mandatory for Admin and Finance roles.
- Account lockout and rate limiting on authentication, MFA, and refresh endpoints.
- Deny-by-default authorization. Every endpoint declares an explicit permission.

### Data and API

- Money `DECIMAL(19,4)`, quantities `DECIMAL(18,4)`; JSON money values are strings.
- RFC 7807 problem details for every error. No stack traces, SQL text, or secrets.
- Pagination is mandatory on list endpoints with a server-enforced maximum (100).
- Idempotency keys on document-creating endpoints.
- OpenAPI is the contract; the frontend calls only documented operations.
- ETag/`If-Match` protects mutable documents from lost updates.

### Audit and retention

- `audit.AuditLog` is append-only with a SHA-256 hash chain, masked before/after values,
  actor, IP, correlation ID, and timestamp, written in the same transaction as the change.
- Runtime logins cannot `UPDATE` or `DELETE` audit rows.
- Soft delete applies to master data and documents; ledgers and audit rows are never
  deletable. See ADR-0003 and ADR-0005.

### Secrets and dependencies

- Only `.env.example` is tracked. `.env` is ignored and contains development-only values.
- CI runs gitleaks, NuGet/npm vulnerability audits, CodeQL, and Trivy filesystem and image
  scans. Critical/High findings block merge.
- New dependencies require Security approval for licence, maintenance, and known CVEs, plus
  an entry in [`docs/DEPENDENCIES.md`](./DEPENDENCIES.md).
- Production secrets belong in a secret manager/KMS, never in images, compose files, or
  source control. Rotation and key custody are gated decisions at the Phase 0 human gate.

### Infrastructure and operations

- Containers run as non-root; the web tier serves a restrictive CSP and proxies same-origin
  API traffic.
- Application database access uses a least-privilege runtime login; schema changes use a
  separate migrator login (ADR-0006). The app never runs migrations at startup.
- Swagger UI is Development-only.
- TLS termination, HSTS, trusted proxy configuration, backup encryption, and restore drills
  are release gates; see `docs/OPERATIONS.md` and the threat model.

## Secure development rules

- Never weaken tests, scanners, or thresholds to pass a gate.
- Never log secrets, tokens, passwords, full tax IDs, bank details, or request bodies that
  may contain them.
- Validate and canonicalize all input at the boundary; parameterize all SQL.
- Enforce authorization server-side; hidden UI controls are not authorization.
- Add abuse-case tests under `tests/security` for every new trust boundary.
- Report a suspected secret leak immediately and rotate the credential; deleting the file
  is not sufficient because Git history retains it.

## Known accepted risks

The Phase 0 threat model records accepted risks with owner and target phase. Notably
M-05 (PII/tax-ID encryption), M-06 (backup encryption and restore drill), and M-07 (MFA
rollout) require explicit human acknowledgement at the Phase 0 gate. Accepted risks are not
waivers for production; each has a closing ticket.
