// Module for networking resources (VNet, Subnets)
targetScope = 'resourceGroup'

@description('Location for resources')
param location string

@description('Application name')
param applicationName string

@description('Environment name')
param environmentName string

@description('Unique suffix for resource names')
param uniqueSuffix string

@description('Tags to apply to resources')
param tags object

// Variables
var vnetName = 'vnet-${applicationName}-${environmentName}-${uniqueSuffix}'
var appGatewaySubnetName = 'snet-appgw'
var containerAppsSubnetName = 'snet-containerApps'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: appGatewaySubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: containerAppsSubnetName
        properties: {
          addressPrefix: '10.0.2.0/23'
          delegations: [
            {
              name: 'Microsoft.App/environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output appGatewaySubnetId string = '${vnet.id}/subnets/${appGatewaySubnetName}'
output containerAppsSubnetId string = '${vnet.id}/subnets/${containerAppsSubnetName}'
