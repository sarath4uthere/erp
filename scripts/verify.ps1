#!/usr/bin/env pwsh
# Full local verification for Mini-ERP. Mirrors the CI gates where they can run locally.
# Usage: pwsh ./scripts/verify.ps1 [-IncludeIntegration] [-ArtifactsPath <dir>]
#        [-SkipFrontend] [-SkipSecurity]
[CmdletBinding()]
param(
    [switch]$IncludeIntegration,
    [string]$ArtifactsPath = $env:ERP_ARTIFACTS_PATH,
    [switch]$SkipFrontend,
    [switch]$SkipSecurity
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function Invoke-Checked {
    param(
        [string]$Label,
        [scriptblock]$Command
    )
    Write-Step $Label
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Get-JsonValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    foreach ($tool in @('dotnet', 'node', 'npm')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Missing required tool: $tool"
        }
    }

    $buildArgs = @('build', 'MiniErp.sln', '--no-restore', '--configuration', 'Release')
    $testArgs = @('test', 'MiniErp.sln', '--configuration', 'Release',
        '--filter', 'Category!=Integration')
    if ($ArtifactsPath) {
        $ArtifactsPath = [System.IO.Path]::GetFullPath($ArtifactsPath)
        New-Item -ItemType Directory -Path $ArtifactsPath -Force | Out-Null
        $testArgs += @('--artifacts-path', $ArtifactsPath)
        Write-Host "Using test artifacts path: $ArtifactsPath"
    }
    else {
        $testArgs += '--no-build'
    }

    Invoke-Checked 'Restore NuGet packages (locked mode)' { dotnet restore --locked-mode }
    Invoke-Checked 'Build backend (Release, warnings as errors)' { & dotnet @buildArgs }
    Invoke-Checked 'Check backend formatting' {
        dotnet format MiniErp.sln --verify-no-changes --no-restore --verbosity minimal
    }
    Invoke-Checked 'Run backend unit and API tests' { & dotnet @testArgs }

    if ($IncludeIntegration) {
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            throw 'Docker is required for -IncludeIntegration.'
        }
        $env:RUN_INTEGRATION_TESTS = 'true'
        try {
            $integrationArgs = @('test', 'tests/IntegrationTests/MiniErp.IntegrationTests.csproj',
                '--configuration', 'Release', '--filter', 'Category=Integration')
            if ($ArtifactsPath) {
                $integrationArgs += @('--artifacts-path', $ArtifactsPath)
            }
            else {
                $integrationArgs += '--no-build'
            }
            Invoke-Checked 'Run Testcontainers integration tests (real SQL Server)' {
                & dotnet @integrationArgs
            }
        }
        finally {
            Remove-Item Env:RUN_INTEGRATION_TESTS -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Warn 'Integration tests skipped. Use -IncludeIntegration with Docker to run them.'
    }

    if (-not $SkipFrontend) {
        if (-not (Test-Path 'web/node_modules')) {
            throw 'web/node_modules is missing. Run scripts/setup-dev first.'
        }
        Invoke-Checked 'Lint frontend' { npm --prefix web run lint }
        Invoke-Checked 'Typecheck frontend' { npm --prefix web run typecheck }
        Invoke-Checked 'Run frontend tests with coverage' { npm --prefix web run test:coverage }
        Invoke-Checked 'Build frontend' { npm --prefix web run build }
    }

    if (-not $SkipSecurity) {
        Invoke-Checked 'Lint OpenAPI contract' {
            npx --yes '@stoplight/spectral-cli@6.17.1' lint openapi/openapi.yaml --fail-severity=error
        }

        Invoke-Checked 'Audit npm dependencies (high and above)' {
            npm --prefix web audit --audit-level=high
        }

        Write-Step 'Audit NuGet dependencies (all projects, including transitive)'
        $auditOutput = & dotnet list MiniErp.sln package --vulnerable --include-transitive --format json
        if ($LASTEXITCODE -ne 0) { throw 'dotnet list package failed.' }
        $audit = $auditOutput | ConvertFrom-Json
        $findings = @()
        foreach ($project in @(Get-JsonValue $audit 'projects')) {
            foreach ($framework in @(Get-JsonValue $project 'frameworks')) {
                $packages = @()
                $packages += @(Get-JsonValue $framework 'topLevelPackages')
                $packages += @(Get-JsonValue $framework 'transitivePackages')
                foreach ($package in $packages) {
                    if ($null -eq $package) { continue }
                    foreach ($vulnerability in @(Get-JsonValue $package 'vulnerabilities')) {
                        if ($null -eq $vulnerability) { continue }
                        $findings += ('{0}: {1} {2} - {3} {4}' -f
                            (Get-JsonValue $project 'path'),
                            (Get-JsonValue $package 'id'),
                            (Get-JsonValue $package 'resolvedVersion'),
                            (Get-JsonValue $vulnerability 'severity'),
                            (Get-JsonValue $vulnerability 'advisoryurl'))
                    }
                }
            }
        }
        if ($findings.Count -gt 0) {
            $findings | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            throw 'Vulnerable NuGet packages detected.'
        }
        Write-Host '    No vulnerable NuGet packages reported.'

        if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
            Invoke-Checked 'Scan working tree for secrets (gitleaks)' {
                gitleaks dir . --redact --config .gitleaks.toml
            }
        }
        else {
            Write-Warn 'gitleaks not installed; secret scan skipped locally. CI enforces it.'
        }

        $dockerComposeAvailable = $false
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            & docker compose version 2>$null | Out-Null
            $dockerComposeAvailable = ($LASTEXITCODE -eq 0)
        }
        if ($dockerComposeAvailable) {
            Invoke-Checked 'Validate Docker Compose configuration' {
                docker compose --env-file .env.example config --quiet
            }
        }
        else {
            Write-Warn 'Docker Compose unavailable; compose validation skipped locally.'
        }
    }

    Write-Host "`nAll executed checks passed." -ForegroundColor Green
    if (-not $IncludeIntegration) {
        Write-Host 'CI still runs Testcontainers, CodeQL, Trivy image scans and container builds.'
    }
}
finally {
    Pop-Location
}
