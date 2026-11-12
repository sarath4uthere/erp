# ADR-0007: OpenAPI-first contract, errors, pagination and idempotency

- Status: Accepted (Phase 0 design; enforced from Phase 1)
- Date: 2026-11-12
- Deciders: Architect, Backend Agent, Frontend Agent, Reviewer
- Related: `PLAN.md` section 5; `docs/THREAT_MODEL.md` sections 5.5, 5.6

## Context

The frontend must be able to code against a stable contract without reading backend code,
and contract drift is a recurring source of broken clients and security gaps (undocumented
endpoints, missing auth). PLAN.md requires the OpenAPI contract to be written before
implementation, frontend code to use only documented endpoints, and contract tests in CI.
It also requires a consistent error format, mandatory pagination and idempotency keys on
document-posting creates.

## Decision

### Source of truth

- `openapi/openapi.yaml` is the authoritative, human-reviewed contract. It is written or
  updated by the Architect in PLAN, before the Backend/Frontend BUILD step.
- The server implements the contract; `swagger.json` is generated for developer
  convenience but is not the source of truth.
- CI lints the contract with Spectral (`--fail-severity=error`) and validates that the
  compose stack is well-formed.
- From Phase 1, a contract test compares the committed spec's paths, methods, request
  bodies and response schemas to the running API in the `Testing` environment. Differences
  fail the build.
- Frontend types/clients are generated from the spec (or hand-written types checked
  against it); no undocumented endpoint may be called. Mocking uses the same contract.

### Versioning

- Base path `/api/v1`. Additive, backward-compatible changes are allowed within v1
  (new optional fields, new endpoints). Breaking changes require `/api/v2` and a
  deprecation window. `/health` remains unversioned.

### Errors

- RFC 7807/9457 `application/problem+json` for every error, including validation,
  401/403, 404, 409, 412, 429 and 5xx.
- Body: `type`, `title`, `status`, `detail`, `instance`, plus extensions `correlationId`,
  `code` (stable machine-readable string) and `errors` (field -> messages) for validation.
- Never leak stack traces, SQL text, connection strings, internal hostnames or entity
  internals. Production exception handling is centralized; Development may add detail but
  never secrets.
- 401 means unauthenticated; 403 means authenticated but not permitted. Object-level
  authorization failures return 404 to avoid enumeration. Validation failures return 400
  with `errors`.

### Collections

- Pagination is mandatory on every list endpoint. Query parameters: `page` (1-based,
  default 1), `pageSize` (default 25, **max 100**, enforced server-side even if the client
  asks for more).
- Response envelope: `{ "items": [...], "total": 1234, "page": 1, "pageSize": 25 }`.
- Sorting: `sort=field` / `sort=-field`, restricted to an explicit allow-list per endpoint;
  unsupported fields return 400. Never pass raw sort/filter text to SQL.
- Filtering: documented, typed parameters; free-text search is capped and parameterized.
- Large exports (Phase 6) have explicit caps and stream/CSV rules; they are separate
  endpoints with their own permissions, not "pageSize=100000".

### Idempotency

- `Idempotency-Key` header is **required** on POSTs that post financial documents: invoice
  issue, payment posting, stock adjustment, journal entry, goods receipt. It is optional
  for drafts and master data.
- Key format: 8-64 visible ASCII characters (UUID/ULID recommended).
- Server stores `(user, endpoint, key)` with a request-body hash, response status/body and
  expiry (24 hours). Same key + same payload returns the original response with
  `Idempotent-Replay: true`. Same key + different payload returns **409**. A concurrent
  duplicate in flight returns 409 (or 425 if the server chooses to wait); clients retry
  with the same key.
- Keys are scoped per user and endpoint; they cannot be used to read another user's
  response.
- The store is a database table with a unique filtered index and a cleanup job; it is not
  an in-memory cache, so restarts do not lose protection.

### Concurrency

- Mutable resources expose `rowversion` as an `ETag`. Mutating requests must send
  `If-Match`; missing precondition returns 428, stale returns 412. The server never
  silently overwrites a concurrent edit.
- Document state transitions are explicit and validated server-side (state machine tests
  in Phase 4). Illegal transitions return 409 with a stable `code`.

### Representation rules

- Money and quantities are strings (ADR-0004). Dates are ISO 8601 UTC or date-only.
- Enums are stable string values, not integers. Unknown enum values are rejected.
- IDs are opaque strings in the contract even if they are GUIDs/ints internally.
- Security schemes: `bearerAuth` for business endpoints; `cookieAuth` only for
  `/api/auth/refresh` and `/api/auth/logout`. Every operation declares its security
  requirement; `/health`, `/api/auth/login` and `/api/auth/refresh` are explicit
  exceptions. A CI check (Phase 1) fails if an operation has no declared security or
  permission.

## Consequences

Positive: clients and tests have one contract; errors are predictable; pagination and
idempotency are not reinvented per module; security review can enumerate every endpoint
and its auth requirement. Negative: contract maintenance is real work; generated clients
need regeneration discipline; idempotency adds a table and cleanup job; `If-Match`
requirements make clients slightly more complex (correctly so).

## Alternatives considered

- Code-first with no committed spec: rejected; the frontend would depend on generated
  artifacts and drift would be invisible.
- GraphQL: out of scope and a poor fit for document-oriented workflows and reporting.
- Offset pagination only: accepted for v1; cursor pagination can be added later behind the
  same envelope for large datasets.
- Client-generated request IDs with no server store: rejected; cannot detect payload
  mismatch or survive restarts.

## Verification

- `openapi/openapi.yaml` passes Spectral with zero errors in CI.
- Phase 1 contract test compares spec and implementation; endpoint authorization matrix
  covers 100% of operations.
- Tests cover problem-details shape, pagination caps, sort allow-list rejection,
  idempotent replay, payload mismatch 409 and stale `If-Match` 412.
