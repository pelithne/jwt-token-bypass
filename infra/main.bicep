// Main Bicep template for JWT Token Test Infrastructure
targetScope = 'subscription'

@description('The location for all resources')
param location string = 'eastus'

@description('Environment name (e.g., dev, test, prod)')
@minLength(3)
@maxLength(10)
param environmentName string = 'dev'

@description('Application name')
@minLength(3)
@maxLength(20)
param applicationName string = 'jwttest'

@description('Azure AD Tenant ID')
param tenantId string

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Application: applicationName
  ManagedBy: 'Bicep'
}

// Variables
var resourceGroupName = 'rg-${applicationName}-${environmentName}-${location}'
var uniqueSuffix = uniqueString(subscription().subscriptionId, resourceGroupName)

// Create resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy Microsoft Entra ID App Registration
module appRegistration 'modules/app-registration.bicep' = {
  name: 'app-registration-deployment'
  scope: resourceGroup
  params: {
    applicationName: applicationName
    environmentName: environmentName
    tenantId: tenantId
    tags: tags
  }
}

// Deploy networking infrastructure
module networking 'modules/networking.bicep' = {
  name: 'networking-deployment'
  scope: resourceGroup
  params: {
    location: location
    applicationName: applicationName
    environmentName: environmentName
    uniqueSuffix: uniqueSuffix
    tags: tags
  }
}

// Deploy Container Registry
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'acr-deployment'
  scope: resourceGroup
  params: {
    location: location
    applicationName: applicationName
    environmentName: environmentName
    uniqueSuffix: uniqueSuffix
    tags: tags
  }
}

// Deploy Container Apps Environment
module containerAppsEnv 'modules/container-apps-environment.bicep' = {
  name: 'containerenv-deployment'
  scope: resourceGroup
  params: {
    location: location
    applicationName: applicationName
    environmentName: environmentName
    uniqueSuffix: uniqueSuffix
    subnetId: networking.outputs.containerAppsSubnetId
    tags: tags
  }
}

// Deploy Backend Container App
module backendApp 'modules/backend-app.bicep' = {
  name: 'backend-deployment'
  scope: resourceGroup
  params: {
    location: location
    applicationName: applicationName
    environmentName: environmentName
    containerAppsEnvironmentId: containerAppsEnv.outputs.environmentId
    containerRegistryName: containerRegistry.outputs.name
    tenantId: tenantId
    clientId: appRegistration.outputs.clientId
    tags: tags
  }
}

// Deploy Application Gateway
module applicationGateway 'modules/application-gateway.bicep' = {
  name: 'appgw-deployment'
  scope: resourceGroup
  params: {
    location: location
    applicationName: applicationName
    environmentName: environmentName
    uniqueSuffix: uniqueSuffix
    subnetId: networking.outputs.appGatewaySubnetId
    backendFqdn: backendApp.outputs.fqdn
    tenantId: tenantId
    clientId: appRegistration.outputs.clientId
    tags: tags
  }
}

// Outputs
output resourceGroupName string = resourceGroup.name
output tenantId string = tenantId
output clientId string = appRegistration.outputs.clientId
output applicationId string = appRegistration.outputs.applicationId
output containerRegistryName string = containerRegistry.outputs.name
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output backendAppFqdn string = backendApp.outputs.fqdn
output applicationGatewayPublicIp string = applicationGateway.outputs.publicIpAddress
output applicationGatewayFqdn string = applicationGateway.outputs.fqdn
