#!/bin/bash
set -e

echo "================================================"
echo "JWT Token Test - Deployment Script"
echo "================================================"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "ERROR: Azure CLI is not installed. Please install it first:"
    echo "   https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "ERROR: You are not logged in to Azure. Please run: az login"
    exit 1
fi

echo "SUCCESS: Azure CLI is installed and you are logged in"
echo ""

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Current Azure Context:"
echo "  Subscription: $SUBSCRIPTION_NAME"
echo "  Subscription ID: $SUBSCRIPTION_ID"
echo "  Tenant ID: $TENANT_ID"
echo ""

read -p "Is this the correct subscription? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please select the correct subscription using: az account set --subscription <subscription-id>"
    exit 1
fi

# Variables
LOCATION=${LOCATION:-eastus}
ENVIRONMENT=${ENVIRONMENT:-dev}
APP_NAME=${APP_NAME:-jwttest}

echo ""
echo "Deployment Configuration:"
echo "  Location: $LOCATION"
echo "  Environment: $ENVIRONMENT"
echo "  Application Name: $APP_NAME"
echo ""

# Step 1: Create Entra ID App Registration
echo "================================================"
echo "Step 1: Creating Microsoft Entra ID App Registration"
echo "================================================"
echo ""

APP_DISPLAY_NAME="${APP_NAME}-${ENVIRONMENT}"

# Check if app already exists
EXISTING_APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)

if [ -n "$EXISTING_APP_ID" ]; then
    echo "WARNING:  App registration '$APP_DISPLAY_NAME' already exists"
    echo "   App ID: $EXISTING_APP_ID"
    CLIENT_ID=$EXISTING_APP_ID
else
    echo "Creating new app registration: $APP_DISPLAY_NAME"
    
    # Create app registration
    CLIENT_ID=$(az ad app create \
        --display-name "$APP_DISPLAY_NAME" \
        --sign-in-audience AzureADMyOrg \
        --enable-id-token-issuance true \
        --public-client-redirect-uris "http://localhost" \
        --query appId -o tsv)
    
    echo "SUCCESS: App registration created"
    echo "   App ID: $CLIENT_ID"
    
    # Get object ID
    OBJECT_ID=$(az ad app show --id "$CLIENT_ID" --query id -o tsv)
    
    # Add API scope
    echo ""
    echo "Adding API scope..."
    
    API_URI="api://${CLIENT_ID}"
    SCOPE_ID=$(uuidgen)
    
    # Create scope JSON with proper structure
    cat > /tmp/scope.json <<EOF
{
    "api": {
        "oauth2PermissionScopes": [
            {
                "adminConsentDescription": "Allow the application to access ${APP_DISPLAY_NAME} on behalf of the signed-in user",
                "adminConsentDisplayName": "Access ${APP_DISPLAY_NAME}",
                "id": "$SCOPE_ID",
                "isEnabled": true,
                "type": "User",
                "userConsentDescription": "Allow the application to access ${APP_DISPLAY_NAME} on your behalf",
                "userConsentDisplayName": "Access ${APP_DISPLAY_NAME}",
                "value": "access_as_user"
            }
        ]
    }
}
EOF
    
    # Update identifier URIs first
    az ad app update --id "$CLIENT_ID" --identifier-uris "$API_URI"
    
    # Then update API scopes
    az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
        --headers "Content-Type=application/json" \
        --body @/tmp/scope.json
    
    rm /tmp/scope.json
    
    echo "SUCCESS: API scope configured"
fi

echo ""
echo "App Registration Details:"
echo "  Display Name: $APP_DISPLAY_NAME"
echo "  Client ID: $CLIENT_ID"
echo "  Tenant ID: $TENANT_ID"
echo "  API Scope: api://${CLIENT_ID}/.default"
echo ""

# Step 2: Update parameters file
echo "================================================"
echo "Step 2: Updating Bicep Parameters"
echo "================================================"
echo ""

PARAMS_FILE="infra/main.bicepparam"
if [ -f "$PARAMS_FILE" ]; then
    # Update tenant ID in parameters file
    sed -i.bak "s/<YOUR_TENANT_ID_HERE>/$TENANT_ID/" "$PARAMS_FILE"
    echo "SUCCESS: Updated $PARAMS_FILE with Tenant ID"
else
    echo "WARNING:  Parameters file not found: $PARAMS_FILE"
fi

# Step 3: Build and push container image
echo ""
echo "================================================"
echo "Step 3: Deploying Infrastructure"
echo "================================================"
echo ""

echo "Deploying Bicep template..."

DEPLOYMENT_NAME="jwt-test-$(date +%Y%m%d-%H%M%S)"

az deployment sub create \
    --name "$DEPLOYMENT_NAME" \
    --location "$LOCATION" \
    --template-file infra/main.bicep \
    --parameters infra/main.bicepparam \
    --parameters tenantId="$TENANT_ID" \
    --query properties.outputs

echo ""
echo "SUCCESS: Infrastructure deployment completed"

# Get outputs
RESOURCE_GROUP=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.resourceGroupName.value -o tsv)
ACR_NAME=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.containerRegistryName.value -o tsv)
ACR_LOGIN_SERVER=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.containerRegistryLoginServer.value -o tsv)
BACKEND_FQDN=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.backendAppFqdn.value -o tsv)
APPGW_FQDN=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs.applicationGatewayFqdn.value -o tsv)

echo ""
echo "Deployment Outputs:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Container Registry: $ACR_NAME"
echo "  Backend FQDN: $BACKEND_FQDN"
echo "  App Gateway FQDN: $APPGW_FQDN"

# Step 4: Build and push container image
echo ""
echo "================================================"
echo "Step 4: Building and Pushing Container Image"
echo "================================================"
echo ""

echo "Logging in to Azure Container Registry..."
az acr login --name "$ACR_NAME"

echo ""
echo "Building Docker image..."
cd backend
docker build -t "$ACR_LOGIN_SERVER/backend:latest" .

echo ""
echo "Pushing image to ACR..."
docker push "$ACR_LOGIN_SERVER/backend:latest"

echo "SUCCESS: Container image pushed successfully"

# Step 5: Update Container App
echo ""
echo "================================================"
echo "Step 5: Updating Container App"
echo "================================================"
echo ""

CONTAINER_APP_NAME=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)

echo "Updating Container App: $CONTAINER_APP_NAME"
az containerapp update \
    --name "$CONTAINER_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --image "$ACR_LOGIN_SERVER/backend:latest" \
    --set-env-vars \
        "AZURE_TENANT_ID=$TENANT_ID" \
        "AZURE_CLIENT_ID=$CLIENT_ID"

echo "SUCCESS: Container App updated"

# Step 6: Configure sender application
echo ""
echo "================================================"
echo "Step 6: Configuring Sender Application"
echo "================================================"
echo ""

cd ../sender

cat > .env <<EOF
# Sender Application Configuration
AZURE_TENANT_ID=$TENANT_ID
AZURE_CLIENT_ID=$CLIENT_ID
API_SCOPE=api://${CLIENT_ID}/.default
BACKEND_ENDPOINT=http://${APPGW_FQDN}/api/protected
EOF

echo "SUCCESS: Created sender/.env file"

# Create Python virtual environment
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

echo "Installing dependencies..."
source venv/bin/activate
pip install -r requirements.txt

echo "SUCCESS: Sender application configured"

# Final summary
echo ""
echo "================================================"
echo "🎉 DEPLOYMENT COMPLETE"
echo "================================================"
echo ""
echo "Summary:"
echo "--------"
echo "SUCCESS: Microsoft Entra ID App Registration created"
echo "   - Client ID: $CLIENT_ID"
echo "   - Tenant ID: $TENANT_ID"
echo ""
echo "SUCCESS: Infrastructure deployed"
echo "   - Resource Group: $RESOURCE_GROUP"
echo "   - Application Gateway: http://${APPGW_FQDN}"
echo "   - Backend Container App: https://${BACKEND_FQDN}"
echo ""
echo "SUCCESS: Container image built and deployed"
echo ""
echo "SUCCESS: Sender application configured"
echo ""
echo "Next Steps:"
echo "-----------"
echo "1. Test the sender application:"
echo "   cd sender"
echo "   source venv/bin/activate"
echo "   python sender.py --endpoint http://${APPGW_FQDN}/api/protected"
echo ""
echo "2. View backend logs:"
echo "   az containerapp logs show \\"
echo "     --name $CONTAINER_APP_NAME \\"
echo "     --resource-group $RESOURCE_GROUP \\"
echo "     --follow"
echo ""
echo "================================================"
