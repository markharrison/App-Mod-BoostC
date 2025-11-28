# Infrastructure Deployment

This folder contains the Bicep templates for deploying the Expense Management System infrastructure to Azure.

## Prerequisites

1. Azure CLI installed and logged in (`az login`)
2. Appropriate Azure subscription permissions
3. Your Azure AD Object ID and User Principal Name

## Getting Your Azure AD Information

```powershell
# Get your Object ID
az ad signed-in-user show --query id -o tsv

# Get your User Principal Name
az ad signed-in-user show --query userPrincipalName -o tsv
```

## Deployment Order Considerations

The deployment is organized in two phases to handle Azure resource dependencies correctly.

### Phase 1: Infrastructure Deployment

Resources must be deployed in this specific order (handled automatically by Bicep dependencies):

1. **Managed Identity** - Created first as other resources depend on it
2. **App Service** - Uses the managed identity for authentication
3. **Azure SQL Server & Database** - Configured with Entra ID authentication
4. **Azure OpenAI** (optional) - Needs managed identity for role assignment
5. **Azure AI Search** (optional) - Needs managed identity for role assignment

### Phase 2: Post-Deployment Configuration

These steps must happen AFTER infrastructure deployment completes:

1. **Wait 30 seconds** - Allow SQL Server to be fully ready
2. **Configure SQL Firewall** - Add your IP for local script execution
3. **Import Database Schema** - Using Python script with Azure AD auth
4. **Configure Managed Identity Roles** - Grant db_datareader/db_datawriter
5. **Create Stored Procedures** - Required by the application
6. **Configure App Settings** (if GenAI) - OpenAI endpoint, deployment name

### Why This Order Matters

- **Bicep cannot configure app settings with GenAI endpoints** because the endpoints don't exist until after deployment
- **SQL Server needs time to be fully ready** before accepting connections
- **Managed Identity must exist before role assignments** can reference it
- **Database schema must exist before stored procedures** can be created

## Deployment Steps

### Step 1: Set PowerShell Variables

```powershell
$resourceGroup = "rg-expensemgmt-demo"
$location = "uksouth"
$adminObjectId = "YOUR_AZURE_AD_OBJECT_ID"  # Replace with output from az ad signed-in-user show --query id -o tsv
$adminLogin = "your.email@domain.com"        # Replace with your UPN
```

### Step 2: Create Resource Group

```powershell
az group create --name $resourceGroup --location $location
```

### Step 3: Deploy Infrastructure (Without GenAI)

```powershell
az deployment group create `
  --resource-group $resourceGroup `
  --template-file ./deploy-infra/main.bicep `
  --parameters location=$location `
  --parameters baseName="expensemgmt" `
  --parameters adminObjectId=$adminObjectId `
  --parameters adminLogin=$adminLogin `
  --parameters deployGenAI=false
```

### Step 3 (Alternative): Deploy Infrastructure (With GenAI)

```powershell
az deployment group create `
  --resource-group $resourceGroup `
  --template-file ./deploy-infra/main.bicep `
  --parameters location=$location `
  --parameters baseName="expensemgmt" `
  --parameters adminObjectId=$adminObjectId `
  --parameters adminLogin=$adminLogin `
  --parameters deployGenAI=true
```

### Step 4: Wait for SQL Server to be Ready

```powershell
Start-Sleep -Seconds 30
```

### Step 5: Add Your IP to SQL Server Firewall

```powershell
$sqlServerName = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.sqlServerName.value" -o tsv)
$myIp = (Invoke-RestMethod -Uri "https://api.ipify.org")
az sql server firewall-rule create --resource-group $resourceGroup --server $sqlServerName --name "LocalMachine" --start-ip-address $myIp --end-ip-address $myIp
```

### Step 6: Import Database Schema

```powershell
$sqlServerName = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.sqlServerName.value" -o tsv)

# Using the Python script for schema import (recommended)
pip3 install --quiet pyodbc azure-identity
python3 run-sql.py
```

### Step 7: Configure Database Roles for Managed Identity

```powershell
# Update the script.sql with the managed identity name
$managedIdentityName = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.managedIdentityName.value" -o tsv)

# Using cross-platform sed (works on Mac and Linux)
sed -i.bak "s/MANAGED-IDENTITY-NAME/$managedIdentityName/g" script.sql; rm -f script.sql.bak

# Run the Python script
python3 run-sql-dbrole.py
```

### Step 8: (If GenAI deployed) Configure App Service with OpenAI Settings

```powershell
$webAppName = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.webAppName.value" -o tsv)
$openAIEndpoint = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.openAIEndpoint.value" -o tsv)
$openAIModelName = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.openAIModelName.value" -o tsv)
$searchEndpoint = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.searchEndpoint.value" -o tsv)
$managedIdentityClientId = (az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs.managedIdentityClientId.value" -o tsv)

az webapp config appsettings set `
  --resource-group $resourceGroup `
  --name $webAppName `
  --settings "OpenAI__Endpoint=$openAIEndpoint" `
             "OpenAI__DeploymentName=$openAIModelName" `
             "Search__Endpoint=$searchEndpoint" `
             "ManagedIdentityClientId=$managedIdentityClientId"
```

## Outputs

After deployment, you can retrieve outputs using:

```powershell
az deployment group show --resource-group $resourceGroup --name main --query "properties.outputs"
```

## Architecture

The infrastructure includes:
- **User-Assigned Managed Identity**: For secure authentication between services
- **App Service (S1)**: Hosts the ASP.NET application
- **Azure SQL Database (Basic)**: Stores expense data with Entra ID authentication only
- **Azure OpenAI (Optional)**: GPT-4o model for chat functionality
- **Azure AI Search (Optional)**: For RAG pattern support

## Bicep Guidelines

- Use `uniqueString(resourceGroup().id)` for deterministic unique names
- Do NOT use `utcNow()` in variable declarations (only allowed in parameter defaults)
- All resource names must be lowercase to comply with Azure naming requirements
- Use null-safe operators (`?.` and `??`) for conditional module outputs
