// Module for creating Microsoft Entra ID App Registration
// NOTE: This is a placeholder. Actual app registration must be done via Azure Portal or Az CLI/PowerShell
// as Bicep does not support Microsoft Graph API operations directly

targetScope = 'resourceGroup'

@description('Application name')
param applicationName string

@description('Environment name')
param environmentName string

@description('Azure AD Tenant ID')
param tenantId string

@description('Tags to apply to resources')
param tags object

// Since we cannot create Entra ID app registration via Bicep directly,
// we output instructions and parameters that will be used

// Output the parameters needed for manual app registration
output appRegistrationInstructions string = '''
IMPORTANT: Microsoft Entra ID App Registration must be created manually.

Follow these steps:

1. Go to Azure Portal > Microsoft Entra ID > App registrations > New registration
2. Name: ${applicationName}-${environmentName}
3. Supported account types: Accounts in this organizational directory only
4. Redirect URI: Public client/native > http://localhost
5. Click Register

6. After registration, note the following:
   - Application (client) ID
   - Directory (tenant) ID

7. Go to "Expose an API":
   - Click "Add a scope"
   - Accept the default Application ID URI: api://{clientId}
   - Scope name: access_as_user
   - Who can consent: Admins and users
   - Admin consent display name: Access ${applicationName}
   - Admin consent description: Allow the application to access ${applicationName} on behalf of the signed-in user
   - State: Enabled

8. Go to "API permissions":
   - The default "User.Read" permission is fine for this demo
   
9. Go to "Authentication":
   - Under "Advanced settings" > "Allow public client flows": Yes
   - Save

10. Update the deployment parameters with the Client ID

For automated deployment, use Azure CLI:
az ad app create --display-name "${applicationName}-${environmentName}" --sign-in-audience AzureADMyOrg --enable-id-token-issuance true --public-client-redirect-uris "http://localhost"
'''

// Placeholder outputs - these should be replaced with actual values after manual registration
output clientId string = 'REPLACE_WITH_YOUR_CLIENT_ID'
output applicationId string = 'REPLACE_WITH_YOUR_CLIENT_ID'
output tenantIdOutput string = tenantId
