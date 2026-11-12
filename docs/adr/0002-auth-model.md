# ADR-0002: Identity, JWT access tokens, rotating refresh cookies, TOTP MFA

- Status: Accepted (Phase 0 design; implementation Phase 1)
- Date: 2026-11-12
- Deciders: Architect, Security Agent, human gate (Phase 1 auth gate)
- Related: `PLAN.md` sections 4 (Phase 1), 6; `docs/THREAT_MODEL.md` sections 5.4, 5.5

## Context

The ERP needs authentication for office clerks, warehouse operators, finance users and
administrators. Sessions must be revocable, resistant to token theft and CSRF, and usable
from a browser SPA without putting long-lived credentials in JavaScript-accessible storage.
PLAN.md requires ASP.NET Identity, short-lived JWT, refresh token rotation with reuse
detection, lockout, password policy, and TOTP MFA for Admin/Finance.

## Decision

### Identity store and passwords

- ASP.NET Identity with the application SQL Server database; no external IdP in v1.
- Identity's PBKDF2 password hasher (v3) is accepted per PLAN.md section 6. Argon2id may
  replace it only with an ADR amendment and a rehash-on-login migration.
- Password policy: minimum 12 characters, no composition rules (length beats complexity),
  reject the configured common-password list, and (Phase 1 optional) HIBP k-anonymity
  check. Passwords are never logged or returned.
- Lockout: 5 failed attempts per account, 15-minute lockout; plus per-IP and per-account
  rate limits on login, refresh, MFA verification and password reset.
- MFA: TOTP (RFC 6238, 6 digits, 30-second step, ±1 step) mandatory for **Admin** and
  **Finance**. Enrollment requires a recent password re-authentication. TOTP secrets are
  encrypted at rest with a key distinct from the JWT key. The last accepted time-step is
  stored to reject replay. Ten single-use recovery codes are stored hashed.

### Access token

- JWT, **15 minutes maximum**, issued by the API. Production lifetime is configurable but
  clamped to <= 15 minutes in code.
- **HS256** with a 64-byte random secret from the secret manager. The validator pins
  `ValidAlgorithms = [HS256]`, `RequireSignedTokens = true`, and validates issuer,
  audience, lifetime and `nbf`/`exp` with 30 seconds of clock skew. Algorithm confusion
  (`alg=none`, RS/HS swap) is therefore rejected.
- Claims: `sub`, `jti`, `sid` (server-side session id), `iss`, `aud`, `iat`, `exp`, `name`,
  `role` (for coarse UI), `perm` (permission claims), `amr` (must include `mfa` for
  MFA-required roles). Tokens contain no PII beyond a display name.
- The SPA keeps the access token **in memory only** (React context/module). It is never
  written to `localStorage`, `sessionStorage`, IndexedDB or a non-HttpOnly cookie.
- Immediate revocation: `sid` is checked against a revocation cache backed by the
  `RevokedSession` table (memory cache, <= 30 s TTL). Logout, password change, role or
  permission change and admin "sign out everywhere" insert a revocation. Residual access
  is bounded by the 15-minute token lifetime.

### Refresh token

- Opaque 256-bit random value, base64url-encoded; only its SHA-256 hash is stored.
- Stored in an **HttpOnly, Secure (production), SameSite=Strict, host-only** cookie:
  `__Secure-erp_rt` in production, `erp_rt` on localhost development. `Path=/api/auth`.
  JavaScript cannot read it.
- Absolute lifetime 7 days. Each successful refresh rotates the token: the old row is
  marked used and a new token in the same **family** is issued. Presentation of an
  already-used token revokes the entire family, all sessions in the family, and raises a
  security event. Concurrent refreshes are serialized per family to avoid false positives.
- Logout, password change, account disable and permission changes revoke the family.
- Cookie flags are configuration-driven but `Secure` and `HttpOnly` are forced in
  non-development environments; startup fails if they are disabled in Production.

### CSRF and CORS

- API calls authenticate with the `Authorization: Bearer` header; they are not
  cookie-authenticated and therefore not CSRF-able.
- The only cookie-authenticated endpoints are `POST /api/auth/refresh` and
  `POST /api/auth/logout`. They require: `SameSite=Strict`, an exact `Origin` (or
  `Referer` fallback) match against the configured allow-list, and the header
  `X-Requested-With: XMLHttpRequest`. Failures return 403 without touching the token.
- CORS is fail-closed and origin-exact. The preferred deployment is same-origin through
  nginx, which removes CORS from the auth path. `AllowCredentials` is enabled only if the
  SPA is deployed cross-origin, which requires a threat-model update.

### Authorization

- Deny-by-default: `FallbackPolicy = RequireAuthenticatedUser`. Every business endpoint
  declares a permission policy, e.g. `[Authorize(Policy = Permissions.Customers.Read)]`.
- Permissions are granular (`customers.read`, `customers.write`, `purchasing.po.approve`,
  `gl.post`, `audit.read`, ...). Roles are bundles of permissions, never hard-coded in
  endpoint logic. Permission claims are issued into the access token; changes trigger
  session revocation.
- Object-level checks are mandatory inside handlers for records with an owner, warehouse,
  customer or organizational scope. Unauthorized object access returns **404**, not 403,
  to avoid identifier enumeration (except where the object's existence is already known
  to the caller).
- Separation of duties is enforced in Application handlers and tested: a PO creator
  cannot approve it; an invoice poster cannot reverse their own posting above the
  configured threshold; admins cannot silently grant themselves finance permissions.

### Login flow

1. `POST /api/auth/login` with email + password (+ TOTP if enrolled / required).
2. On success: access token in the JSON response; refresh cookie set; `sid` created;
   audit event written. MFA-required roles without enrollment receive a
   `mfa_enrollment_required` challenge, not a token.
3. SPA stores the access token in memory and schedules a refresh before expiry.
4. On page reload the SPA calls `POST /api/auth/refresh` (cookie) to obtain a new access
   token. If refresh fails, it shows the login screen.
5. `POST /api/auth/logout` revokes the family, clears the cookie and the in-memory token.

## Consequences

Positive: no long-lived token in JavaScript; refresh theft is detectable and revocable;
CSRF surface is small and explicitly defended; authorization is centralized and testable.

Negative / risks: a 15-minute revocation window for access tokens (mitigated by the
revocation cache); refresh concurrency needs careful implementation; TOTP enrollment adds
support burden; HS256 requires strong key custody and rotation discipline (a `kid` header
is reserved for dual-key rotation).

## Alternatives considered

- Access token in `localStorage`: rejected (XSS becomes full account takeover).
- Refresh token in JavaScript: rejected (same reason, longer window).
- Cookie-only sessions for the API: viable, but conflicts with PLAN.md's JWT requirement
  and would require full CSRF tokens on every mutation. The chosen split keeps bearer
  calls CSRF-free and confines cookies to two endpoints.
- RS256: stronger key separation but adds key distribution complexity for a single API.
  Revisit if an external IdP or multiple services appear.
- External OIDC provider: deferred; local Identity is fixed by the plan and is sufficient
  for one tenant.

## Verification

Phase 1 security tests: `JwtValidationTests`, `TokenReplayTests`, `RefreshReuseTests`,
`CookieCsrfTests`, `LockoutTests`, `TotpTests`, `ForwardedHeaderSpoofTests`, plus the
endpoint authorization matrix (allowed / forbidden / anonymous). The threat model's
SEC-AUTH*, SEC-JWT*, SEC-REFRESH*, SEC-CSRF*, SEC-MFA* rows are the acceptance list.
