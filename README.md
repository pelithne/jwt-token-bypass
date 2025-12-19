# JWT Authentication with Azure Container Apps and Application Gateway

End-to-end JWT authentication demonstration using Microsoft Entra ID, Azure Container Apps, and Application Gateway.

## Architecture

```
Local Sender (MSAL) → Application Gateway (WAF) → Container App (JWT Validation)
```

## Prerequisites

- Azure CLI >= 2.50.0
- Docker >= 20.10
- Python >= 3.11
- Azure subscription with resource creation permissions

## Quick Start

```bash
# Clone repository (no authentication required for public repo)
git clone https://github.com/pelithne/jwt-token-bypass.git
cd jwt-token-bypass

# Login
az login
az account set --subscription <subscription-id>

# Deploy infrastructure
./scripts/deploy.sh

# Test
cd sender
export AZURE_TENANT_ID=<tenant-id>
export AZURE_CLIENT_ID=<client-id>
export API_SCOPE=api://<client-id>/access_as_user
python sender.py --endpoint http://<appgw-fqdn>/api/protected
```

Values displayed after deployment.

## Components

- **Backend**: Flask API with JWT validation (PyJWT + JWKS)
- **Sender**: MSAL Python client with interactive auth
- **Infrastructure**: Bicep templates for Azure resources

## Deployment Script Actions

1. Creates Entra ID app registration with API scope
2. Deploys infrastructure (VNet, ACR, Container Apps, App Gateway)
3. Builds and pushes container image
4. Configures environment variables
5. Sets up sender application

## API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/` | GET | No | Health check |
| `/api/protected` | GET | Yes | Protected resource |
| `/api/token-info` | POST | Yes | Token claims |

## Manual Deployment

### App Registration

```bash
az ad app create --display-name "jwttest-dev" \
  --sign-in-audience AzureADMyOrg \
  --enable-id-token-issuance true \
  --public-client-redirect-uris "http://localhost"

```

### Infrastructure

```bash
cd infra
az deployment sub create \
  --location swedencentral \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### Container

```bash
cd backend
az acr login --name <registry>
docker build -t backend:latest .
docker tag backend:latest <registry>.azurecr.io/backend:latest
docker push <registry>.azurecr.io/backend:latest
```

### Update App

```bash
az containerapp update \
  --name <app> \
  --resource-group <rg> \
  --set-env-vars "AZURE_TENANT_ID=<tenant>" "AZURE_CLIENT_ID=<client>"
```


## Cleanup

```bash
az group delete --name rg-jwttest-dev-swedencentral --yes
az ad app delete --id <client-id>
```


## License

MIT
