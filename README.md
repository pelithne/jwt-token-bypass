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
cd jwt-token-test

# Login
az login
az account set --subscription <subscription-id>

# Deploy
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

## Configuration

**Infrastructure** (infra/main.bicepparam):
```bicep
param location = 'swedencentral'
param environmentName = 'dev'
param applicationName = 'jwttest'
param tenantId = 'YOUR_TENANT_ID'
```

**Backend Environment Variables**:
- `AZURE_TENANT_ID`: Tenant ID
- `AZURE_CLIENT_ID`: App registration client ID
- `PORT`: HTTP port (default: 8080)

**Sender Environment Variables**:
- `AZURE_TENANT_ID`: Tenant ID
- `AZURE_CLIENT_ID`: App registration client ID
- `API_SCOPE`: OAuth scope (api://client-id/access_as_user)
- `BACKEND_ENDPOINT`: Application Gateway URL

## JWT Validation

Validates: signature (JWKS), issuer (v1.0/v2.0), audience (api://client-id), expiration (exp/nbf/iat), algorithm (RS256).

## Manual Deployment

### App Registration

```bash
az ad app create --display-name "jwttest-dev" \
  --sign-in-audience AzureADMyOrg \
  --enable-id-token-issuance true \
  --public-client-redirect-uris "http://localhost"

# Add scope
./scripts/fix-app-registration.sh
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

## Troubleshooting

**WAF 403 Errors**:
```bash
az network application-gateway waf-policy policy-setting update \
  --policy-name <waf> --resource-group <rg> --mode Detection
```

**Backend Health**:
```bash
az containerapp show --name <app> -g <rg> \
  --query "properties.{status:runningStatus,fqdn:configuration.ingress.fqdn}"

az containerapp logs show --name <app> -g <rg> --tail 50
```

**Token Issues**:
```bash
az ad app show --id <client-id> \
  --query "{identifierUris:identifierUris,scopes:api.oauth2PermissionScopes[*].value}"
```

## Cleanup

```bash
az group delete --name rg-jwttest-dev-swedencentral --yes
az ad app delete --id <client-id>
```

## Cost Estimate

Monthly: Application Gateway WAF_v2 ($300) + Container Apps ($20) + ACR ($20) + Other ($10) = ~$350

## Security

- WAF enabled (Detection mode for testing)
- Managed identity for ACR
- No credentials in code
- JWT validation at app level
- Microsoft JWKS validation

## License

MIT
