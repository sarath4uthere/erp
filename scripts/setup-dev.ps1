#!/usr/bin/env pwsh
# First-time developer setup for Mini-ERP.
# Usage: pwsh ./scripts/setup-dev.ps1 [-SkipRestore] [-SkipWeb]
[CmdletBinding()]
param(
    [switch]$SkipRestore,
    [switch]$SkipWeb
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    Write-Step "Checking required tools"
    $missing = @()
    foreach ($tool in @('git', 'dotnet', 'node', 'npm')) {
        if (-not (Test-Command $tool)) {
            $missing += $tool
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing required tool(s): $($missing -join ', '). Install them and re-run."
    }

    $nodeVersion = ((& node --version).TrimStart('v'))
    if ([version]$nodeVersion -lt [version]'22.12.0') {
        throw "Node.js $nodeVersion is too old; install >= 22.12.0."
    }
    Write-Host "    git $(git --version), dotnet $((& dotnet --version)), node $nodeVersion, npm $((& npm --version))"

    if (Test-Command docker) {
        try {
            & docker compose version | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'docker compose returned a non-zero exit code.' }
        }
        catch {
            Write-Warn 'Docker Compose v2 is unavailable. Container and integration tests will not run locally.'
        }
    }
    else {
        Write-Warn 'Docker is not installed. Container builds, compose, and Testcontainers will not run locally.'
    }

    if (-not (Test-Command 'gitleaks')) {
        Write-Warn 'gitleaks is not installed; the pre-commit hook will skip the local secret scan. CI still enforces it.'
    }

    Write-Step "Configuring git hooks"
    & git config core.hooksPath .githooks
    if ($LASTEXITCODE -ne 0) { throw 'Failed to set core.hooksPath.' }

    Write-Step "Preparing local environment"
    if (Test-Path '.env') {
        Write-Host '    .env already exists; leaving it untouched.'
    }
    else {
        Copy-Item '.env.example' '.env'
        Write-Host '    Created .env from .env.example (development placeholders only).'
    }

    if (-not $SkipRestore) {
        Write-Step "Restoring NuGet packages"
        & dotnet restore --locked-mode
        if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }
    }

    if (-not $SkipWeb) {
        Write-Step "Installing web dependencies from package-lock.json"
        & npm --prefix web ci --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    }

    if (Test-Command docker) {
        Write-Step "Validating Docker Compose configuration"
        & docker compose --env-file .env.example config --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'Compose validation failed. Check .env.example and docker-compose.yml.'
        }
    }

    Write-Host ''
    Write-Host 'Setup complete. Next steps:' -ForegroundColor Green
    Write-Host '  pwsh ./scripts/verify.ps1                 # full local verification'
    Write-Host '  pwsh ./scripts/verify.ps1 -IncludeIntegration  # requires Docker'
    Write-Host '  docker compose up --build                 # run SQL Server + API + web'
    Write-Host '  dotnet run --project src/Api              # or run layers directly'
    Write-Host '  npm --prefix web run dev'
}
finally {
    Pop-Location
}
