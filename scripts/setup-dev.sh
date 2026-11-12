#!/usr/bin/env bash
# First-time developer setup for Mini-ERP.
# Usage: ./scripts/setup-dev.sh [--skip-restore] [--skip-web]
set -euo pipefail

skip_restore=0
skip_web=0
for arg in "$@"; do
  case "$arg" in
    --skip-restore) skip_restore=1 ;;
    --skip-web) skip_web=1 ;;
    -h|--help)
      echo "Usage: $0 [--skip-restore] [--skip-web]"
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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

step "Checking required tools"
missing=()
for tool in git dotnet node npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing+=("$tool")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required tool(s): ${missing[*]}. Install them and re-run." >&2
  exit 1
fi

node_version="$(node --version | sed 's/^v//')"
node_major="${node_version%%.*}"
node_rest="${node_version#*.}"
node_minor="${node_rest%%.*}"
if [ "$node_major" -lt 22 ] || { [ "$node_major" -eq 22 ] && [ "$node_minor" -lt 12 ]; }; then
  echo "Node.js $node_version is too old; install >= 22.12.0." >&2
  exit 1
fi
printf '    git %s, dotnet %s, node %s, npm %s\n' \
  "$(git --version)" "$(dotnet --version)" "$node_version" "$(npm --version)"

docker_ok=0
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker_ok=1
else
  warn "Docker Compose v2 is unavailable. Container builds, compose, and Testcontainers will not run locally."
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  warn "gitleaks is not installed; the pre-commit hook will skip the local secret scan. CI still enforces it."
fi

step "Configuring git hooks"
git config core.hooksPath .githooks

step "Preparing local environment"
if [ -f .env ]; then
  echo "    .env already exists; leaving it untouched."
else
  cp .env.example .env
  echo "    Created .env from .env.example (development placeholders only)."
fi

if [ "$skip_restore" -eq 0 ]; then
  step "Restoring NuGet packages"
  dotnet restore --locked-mode
fi

if [ "$skip_web" -eq 0 ]; then
  step "Installing web dependencies from package-lock.json"
  npm --prefix web ci --no-audit --no-fund
fi

if [ "$docker_ok" -eq 1 ]; then
  step "Validating Docker Compose configuration"
  if ! docker compose --env-file .env.example config --quiet; then
    warn "Compose validation failed. Check .env.example and docker-compose.yml."
  fi
fi

cat <<'EOF'

Setup complete. Next steps:
  ./scripts/verify.sh                          # full local verification
  RUN_INTEGRATION_TESTS=true ./scripts/verify.sh  # requires Docker
  docker compose up --build                    # run SQL Server + API + web
  dotnet run --project src/Api                 # or run layers directly
  npm --prefix web run dev

EOF
