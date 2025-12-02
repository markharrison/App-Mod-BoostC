# cleanup-github-azure-oidc.ps1 - Remove Azure OIDC authentication for GitHub Actions
# This script deletes the Azure AD App Registration and Service Principal created
# for GitHub Actions authentication.
#
# Prerequisites:
# - Azure CLI installed and logged in (az login)
#
# Usage: .\cleanup-github-azure-oidc.ps1

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GitHub Actions Azure OIDC Cleanup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Configuration
$APP_NAME = $null
$ENVIRONMENT = $null

# Read APP_NAME and ENVIRONMENT from oidc-env.txt if present, otherwise prompt
$envFile = Join-Path $PSScriptRoot "oidc-env.txt"
if (Test-Path $envFile) {
    $envVars = Get-Content $envFile | Where-Object { $_ -match '=' }
    foreach ($line in $envVars) {
        $parts = $line -split '=', 2
        if ($parts[0] -eq 'APP_NAME') { $APP_NAME = $parts[1] }
        if ($parts[0] -eq 'ENVIRONMENT') { $ENVIRONMENT = $parts[1] }
    }
}
if (-not $APP_NAME) { $APP_NAME = Read-Host 'Enter APP_NAME' }
if (-not $ENVIRONMENT) { $ENVIRONMENT = Read-Host 'Enter environment name (e.g. production, staging)' }

# Get App ID
Write-Host ""
Write-Host "Step 1: Finding Azure AD App Registration..." -ForegroundColor Yellow
$APP_ID = az ad app list --display-name $APP_NAME --query [0].appId -o tsv

if ([string]::IsNullOrEmpty($APP_ID)) {
    Write-Host "✗ App Registration '$APP_NAME' not found" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Found App ID: $APP_ID" -ForegroundColor Green

# Delete App Registration (this also deletes the Service Principal)
Write-Host ""
Write-Host "Step 2: Deleting App Registration and Service Principal..." -ForegroundColor Yellow
az ad app delete --id $APP_ID

Write-Host "✓ App Registration and Service Principal deleted" -ForegroundColor Green

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Cleanup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The Azure AD App Registration '$APP_NAME' has been deleted." -ForegroundColor Green
Write-Host "Note: Role assignments are automatically removed when the Service Principal is deleted." -ForegroundColor Gray
Write-Host ""
