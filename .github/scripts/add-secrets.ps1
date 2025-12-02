# add-github-secrets.ps1 - Add GitHub secrets for Azure OIDC authentication
# This script uses GitHub CLI to add the required secrets to the repository
#
# Prerequisites:
# - GitHub CLI installed (gh)
# - Authenticated with GitHub (gh auth login)
#
# Usage: .\add-github-secrets.ps1

# Check GitHub authentication
Write-Host "Checking GitHub authentication..." -ForegroundColor Yellow
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Not authenticated with GitHub" -ForegroundColor Red
    Write-Host "Please run: gh auth login" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Authenticated with GitHub" -ForegroundColor Green
Write-Host ""

# Configuration - Get repo from git remote
$gitRemote = git remote get-url origin
$GITHUB_REPO = $gitRemote -replace '^https://github.com/', '' -replace '\.git$', ''


# Read values from oidc-env.txt if present, otherwise prompt for each value
$envFile = Join-Path $PSScriptRoot "oidc-env.txt"
$ENVIRONMENT = $null
if (Test-Path $envFile) {
    $envVars = Get-Content $envFile | Where-Object { $_ -match '=' }
    foreach ($line in $envVars) {
        $parts = $line -split '=', 2
        $key = $parts[0]
        $val = $parts[1]
        switch ($key) {
            'AZURE_CLIENT_ID' { $ClientId = $val }
            'AZURE_TENANT_ID' { $TenantId = $val }
            'AZURE_SUBSCRIPTION_ID' { $SubscriptionId = $val }
            'APP_NAME' { $AppName = $val }
            'ENVIRONMENT' { $ENVIRONMENT = $val }
        }
    }
}
if (-not $ClientId) { $ClientId = Read-Host 'Enter AZURE_CLIENT_ID' }
if (-not $TenantId) { $TenantId = Read-Host 'Enter AZURE_TENANT_ID' }
if (-not $SubscriptionId) { $SubscriptionId = Read-Host 'Enter AZURE_SUBSCRIPTION_ID' }
if (-not $AppName) { $AppName = Read-Host 'Enter APP_NAME' }
while (-not $ENVIRONMENT) {
    $ENVIRONMENT = Read-Host 'Enter environment name (e.g. production, staging)'
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Add GitHub Secrets" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository: $GITHUB_REPO" -ForegroundColor Gray
Write-Host ""


# Add secrets to the specified GitHub Environment
Write-Host "Adding AZURE_CLIENT_ID to environment '$ENVIRONMENT'..." -ForegroundColor Yellow
$ClientId | gh secret set AZURE_CLIENT_ID --repo $GITHUB_REPO --env "$ENVIRONMENT"

Write-Host ""
Write-Host "Adding AZURE_TENANT_ID to environment '$ENVIRONMENT'..." -ForegroundColor Yellow
$TenantId | gh secret set AZURE_TENANT_ID --repo $GITHUB_REPO --env "$ENVIRONMENT"

Write-Host ""
Write-Host "Adding AZURE_SUBSCRIPTION_ID to environment '$ENVIRONMENT'..." -ForegroundColor Yellow
$SubscriptionId | gh secret set AZURE_SUBSCRIPTION_ID --repo $GITHUB_REPO --env "$ENVIRONMENT"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Secrets Added Successfully!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verifying secrets..." -ForegroundColor Yellow
gh secret list --repo $GITHUB_REPO
Write-Host ""
Write-Host "You can now run the GitHub Actions workflow." -ForegroundColor Green
Write-Host ""
