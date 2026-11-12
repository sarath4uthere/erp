#!/usr/bin/env bash
# Full local verification for Mini-ERP. Mirrors the CI gates where they can run locally.
# Usage: ./scripts/verify.sh [--include-integration] [--skip-frontend] [--skip-security]
# Env:   ERP_ARTIFACTS_PATH  build/test artifacts directory (Windows app-control workaround)
set -euo pipefail

include_integration=0
skip_frontend=0
skip_security=0
for arg in "$@"; do
  case "$arg" in
    --include-integration) include_integration=1 ;;
    --skip-frontend) skip_frontend=1 ;;
    --skip-security) skip_security=1 ;;
    -h|--help)
      echo "Usage: $0 [--include-integration] [--skip-frontend] [--skip-security]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1" >&2; }

run() {
  local label="$1"
  shift
  step "$label"
  "$@"
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for tool in dotnet node npm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done

artifacts_path="${ERP_ARTIFACTS_PATH:-}"
build_args=(build MiniErp.sln --no-restore --configuration Release)
test_args=(test MiniErp.sln --configuration Release --filter "Category!=Integration")
if [ -n "$artifacts_path" ]; then
  mkdir -p "$artifacts_path"
  artifacts_path="$(cd "$artifacts_path" && pwd)"
  test_args+=(--artifacts-path "$artifacts_path")
  printf 'Using test artifacts path: %s\n' "$artifacts_path"
else
  test_args+=(--no-build)
fi

run "Restore NuGet packages (locked mode)" dotnet restore --locked-mode
run "Build backend (Release, warnings as errors)" dotnet "${build_args[@]}"
run "Check backend formatting" dotnet format MiniErp.sln --verify-no-changes --no-restore --verbosity minimal
run "Run backend unit and API tests" dotnet "${test_args[@]}"

if [ "$include_integration" -eq 1 ]; then
  command -v docker >/dev/null 2>&1 || { echo "Docker is required for --include-integration." >&2; exit 1; }
  integration_args=(test tests/IntegrationTests/MiniErp.IntegrationTests.csproj --configuration Release --filter "Category=Integration")
  if [ -n "$artifacts_path" ]; then
    integration_args+=(--artifacts-path "$artifacts_path")
  else
    integration_args+=(--no-build)
  fi
  step "Run Testcontainers integration tests (real SQL Server)"
  RUN_INTEGRATION_TESTS=true dotnet "${integration_args[@]}"
else
  warn "Integration tests skipped. Use --include-integration with Docker to run them."
fi

if [ "$skip_frontend" -eq 0 ]; then
  if [ ! -d web/node_modules ]; then
    echo "web/node_modules is missing. Run scripts/setup-dev first." >&2
    exit 1
  fi
  run "Lint frontend" npm --prefix web run lint
  run "Typecheck frontend" npm --prefix web run typecheck
  run "Run frontend tests with coverage" npm --prefix web run test:coverage
  run "Build frontend" npm --prefix web run build
fi

if [ "$skip_security" -eq 0 ]; then
  run "Lint OpenAPI contract" npx --yes @stoplight/spectral-cli@6.17.1 lint openapi/openapi.yaml --fail-severity=error
  run "Audit npm dependencies (high and above)" npm --prefix web audit --audit-level=high

  step "Audit NuGet dependencies (all projects, including transitive)"
  audit_json="$(dotnet list MiniErp.sln package --vulnerable --include-transitive --format json)"
  if ! printf '%s' "$audit_json" | node -e '
let raw = "";
process.stdin.on("data", (chunk) => { raw += chunk; });
process.stdin.on("end", () => {
  let data;
  try { data = JSON.parse(raw); }
  catch (error) { console.error("Could not parse dotnet audit JSON: " + error.message); process.exit(2); }

  const findings = [];
  for (const project of data.projects || []) {
    for (const framework of project.frameworks || []) {
      const packages = [...(framework.topLevelPackages || []), ...(framework.transitivePackages || [])];
      for (const pkg of packages) {
        for (const vulnerability of pkg.vulnerabilities || []) {
          findings.push(`${project.path || project.name || "?"}: ${pkg.id} ${pkg.resolvedVersion} - ${vulnerability.severity} ${vulnerability.advisoryurl || ""}`);
        }
      }
    }
  }
  if (findings.length > 0) { console.error(findings.join("\n")); process.exit(1); }
});'; then
    echo "Vulnerable NuGet packages detected." >&2
    exit 1
  fi
  echo "    No vulnerable NuGet packages reported."

  if command -v gitleaks >/dev/null 2>&1; then
    run "Scan working tree for secrets (gitleaks)" gitleaks dir . --redact --config .gitleaks.toml
  else
    warn "gitleaks not installed; secret scan skipped locally. CI enforces it."
  fi

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    run "Validate Docker Compose configuration" docker compose --env-file .env.example config --quiet
  else
    warn "Docker Compose unavailable; compose validation skipped locally."
  fi
fi

printf '\nAll executed checks passed.\n'
if [ "$include_integration" -eq 0 ]; then
  echo "CI still runs Testcontainers, CodeQL, Trivy image scans and container builds."
fi
