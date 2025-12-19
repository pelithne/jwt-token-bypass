using './main.bicep'

// Required parameters
param location = 'swedencentral'
param environmentName = 'dev'
param applicationName = 'jwttest'
param tenantId = 'YOUR_TENANT_ID'

// Optional tags
param tags = {
  Environment: 'Development'
  Project: 'JWT Token Test'
  ManagedBy: 'Bicep'
}
