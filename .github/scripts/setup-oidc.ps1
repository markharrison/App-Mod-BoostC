# setup-github-azure-oidc.ps1 - Configure Azure OIDC authentication for GitHub Actions
# This script sets up the Azure AD App Registration and Service Principal needed
# for GitHub Actions to authenticate to Azure without storing credentials.
#
# Prerequisites:
# - Azure CLI installed and logged in (az login)
# - Contributor access to the subscription
#
# Usage: .\setup-github-azure-oidc.ps1

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GitHub Actions Azure OIDC Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Configuration
$APP_NAME = $null
$envFile = Join-Path $PSScriptRoot "oidc-env.txt"
if (Test-Path $envFile) {
    $envVars = Get-Content $envFile | Where-Object { $_ -match '=' }
    foreach ($line in $envVars) {
        $parts = $line -split '=', 2
        if ($parts[0] -eq 'APP_NAME') { $APP_NAME = $parts[1] }
    }
}


# Get repo from git remote, validate, and prompt if needed
$gitRemote = git remote get-url origin 2>$null
Write-Host "[DEBUG] git remote: $gitRemote" -ForegroundColor DarkGray
$GITHUB_REPO = $null
if ($gitRemote) {
    # Try to extract owner/repo from HTTPS URL
    if ($gitRemote -match '^https://github.com/([^/]+/[^/]+)(\.git)?$') {
        $GITHUB_REPO = $Matches[1]
    }
    # Try to extract owner/repo from SSH URL
    elseif ($gitRemote -match '^git@github.com:([^/]+/[^/]+)(\.git)?$') {
        $GITHUB_REPO = $Matches[1]
    }
    # Try to extract from any github.com URL
    elseif ($gitRemote -match 'github.com[:/]+([^/]+/[^/]+)(\.git)?$') {
        $GITHUB_REPO = $Matches[1]
    }
}
Write-Host "[DEBUG] Extracted GITHUB_REPO: $GITHUB_REPO" -ForegroundColor DarkGray
# Validate format (should be owner/repo)
while (-not $GITHUB_REPO -or $GITHUB_REPO -notmatch '^[^/]+/[^/]+$') {
    $GITHUB_REPO = Read-Host 'Enter GitHub repository (format: owner/repo, e.g. markharrison/App-Mod-BoostC)'
    Write-Host "[DEBUG] User entered GITHUB_REPO: $GITHUB_REPO" -ForegroundColor DarkGray
}

# Get branch name from current branch or prompt
$GITHUB_BRANCH = $null
try {
    $GITHUB_BRANCH = git rev-parse --abbrev-ref HEAD 2>$null
} catch {}
if (-not $GITHUB_BRANCH -or $GITHUB_BRANCH -eq 'HEAD') {
    $GITHUB_BRANCH = Read-Host 'Enter branch name (e.g. main)'
}

# Prompt for APP_NAME if not set by file or environment
while (-not $APP_NAME) {
    $APP_NAME = Read-Host 'Enter APP_NAME (Azure AD App Registration name)'
}

# Get current subscription
Write-Host ""
Write-Host "Step 1: Getting subscription details..." -ForegroundColor Yellow
$SUBSCRIPTION_ID = az account show --query id -o tsv
$TENANT_ID = az account show --query tenantId -o tsv

Write-Host "✓ Subscription ID: $SUBSCRIPTION_ID" -ForegroundColor Green
Write-Host "✓ Tenant ID: $TENANT_ID" -ForegroundColor Green

# Create Azure AD App Registration
Write-Host ""
Write-Host "Step 2: Creating Azure AD App Registration..." -ForegroundColor Yellow
az ad app create --display-name $APP_NAME --output none 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "App may already exist" -ForegroundColor Gray }

$APP_ID = az ad app list --display-name $APP_NAME --query [0].appId -o tsv
Write-Host "✓ App ID (Client ID): $APP_ID" -ForegroundColor Green

# Create Service Principal
Write-Host ""
Write-Host "Step 3: Creating Service Principal..." -ForegroundColor Yellow
az ad sp create --id $APP_ID --output none 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "Service Principal may already exist" -ForegroundColor Gray }

$OBJECT_ID = az ad sp list --display-name $APP_NAME --query [0].id -o tsv
Write-Host "✓ Service Principal Object ID: $OBJECT_ID" -ForegroundColor Green

# Add federated credential for specified branch
Write-Host "" 
Write-Host "Step 4: Adding federated credential for branch $GITHUB_BRANCH..." -ForegroundColor Yellow

# Use a safe federated credential name (replace / with -)
$safeBranch = $GITHUB_BRANCH -replace '[^a-zA-Z0-9_-]', '-'
$credName = "gh-expensemgmt-$safeBranch"


# Create JSON file with proper formatting for GitHub Actions OIDC
$GITHUB_REPO = "$GITHUB_REPO"  # Force as string
if (-not $GITHUB_REPO -or $GITHUB_REPO -eq "") {
    Write-Host "[ERROR] GITHUB_REPO is empty. This should never happen." -ForegroundColor Red
    exit 1
}
$subject = "repo:$($GITHUB_REPO):ref:refs/heads/$GITHUB_BRANCH"
Write-Host "[DEBUG] Federated credential subject: $subject" -ForegroundColor DarkGray
$fedcred = @{
    name = $credName
    issuer = "https://token.actions.githubusercontent.com"
    subject = $subject
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json -Compress
$fedcredPath = "fedcred.json"
$fedcred | Out-File -FilePath $fedcredPath -Encoding utf8

# Delete existing credentials if they exist
az ad app federated-credential delete --id $APP_ID --federated-credential-id $credName 2>$null

# Create new credential and capture output
Write-Host "Creating federated credential (for GitHub Actions OIDC, scenario will show as 'Other issuer' in portal, but this is correct)..." -ForegroundColor Yellow
$fcResult = az ad app federated-credential create --id $APP_ID --parameters @$fedcredPath
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Federated credential created for repo: $GITHUB_REPO (branch $GITHUB_BRANCH)" -ForegroundColor Green
    Write-Host "  Subject: $subject" -ForegroundColor Gray
    Write-Host "  Issuer: https://token.actions.githubusercontent.com" -ForegroundColor Gray
    Write-Host "  Audience: api://AzureADTokenExchange" -ForegroundColor Gray
    Write-Host "  NOTE: In the Azure Portal, the scenario will show as 'Other issuer' but this is correct for automation." -ForegroundColor Yellow
} else {
    Write-Host "✗ Failed to create federated credential. See output above." -ForegroundColor Red
}

# Print the full federated credential subject, issuer, and audience for manual verification in Azure Portal
Write-Host "" -ForegroundColor Yellow
Write-Host "==== Federated Credential Details for Azure Portal Verification ====" -ForegroundColor Cyan
Write-Host "Issuer:    https://token.actions.githubusercontent.com" -ForegroundColor White
Write-Host "Subject:   $subject" -ForegroundColor White
Write-Host "Audience:  api://AzureADTokenExchange" -ForegroundColor White
Write-Host "(Copy these values to verify in the Azure Portal if needed)" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan

# Cleanup
Remove-Item -Path $fedcredPath -Force

# Verify federated credential exists
Write-Host "" 
Write-Host "Step 6: Verifying federated credential..." -ForegroundColor Yellow
$fcList = az ad app federated-credential list --id $APP_ID | ConvertFrom-Json
$fcFound = $fcList | Where-Object { $_.name -eq $credName }
if ($fcFound) {
    Write-Host "✓ Federated credential verified: $($fcFound.name)" -ForegroundColor Green
} else {
    Write-Host "✗ Federated credential NOT found!" -ForegroundColor Red
}

# Assign Contributor role
Write-Host ""
Write-Host "Step 5: Assigning Contributor role..." -ForegroundColor Yellow
az role assignment create `
  --assignee $OBJECT_ID `
  --role Contributor `
  --scope "/subscriptions/$SUBSCRIPTION_ID" `
  --output none 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "Role assignment may already exist" -ForegroundColor Gray }

Write-Host "✓ Contributor role assigned" -ForegroundColor Green

# Write values to a file for use by add-secrets and cleanup-oidc
$envFile = Join-Path $PSScriptRoot "oidc-env.txt"
@(
    "AZURE_CLIENT_ID=$APP_ID",
    "AZURE_TENANT_ID=$TENANT_ID",
    "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID",
    "APP_NAME=$APP_NAME"
) | Set-Content -Path $envFile -Encoding utf8
Write-Host "OIDC environment values written to $envFile" -ForegroundColor Green

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Add these secrets to GitHub:" -ForegroundColor Yellow
Write-Host "  Repository: https://github.com/${GITHUB_REPO}/settings/secrets/actions" -ForegroundColor Gray
Write-Host ""
Write-Host "AZURE_CLIENT_ID=$APP_ID" -ForegroundColor White
Write-Host "AZURE_TENANT_ID=$TENANT_ID" -ForegroundColor White
Write-Host "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Go to GitHub repository settings" -ForegroundColor Gray
Write-Host "2. Navigate to: Settings → Secrets and variables → Actions" -ForegroundColor Gray
Write-Host "3. Click 'New repository secret' and add each secret above" -ForegroundColor Gray
Write-Host "4. Go to Actions tab and run the 'Deploy Expense Management System' workflow" -ForegroundColor Gray
Write-Host ""
