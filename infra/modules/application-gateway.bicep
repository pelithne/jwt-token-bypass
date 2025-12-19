// Module for Application Gateway with JWT validation
targetScope = 'resourceGroup'

@description('Location for resources')
param location string

@description('Application name')
param applicationName string

@description('Environment name')
param environmentName string

@description('Unique suffix for resource names')
param uniqueSuffix string

@description('Subnet ID for Application Gateway')
param subnetId string

@description('Backend FQDN (Container App)')
param backendFqdn string

@description('Azure AD Tenant ID for JWT validation')
param tenantId string

@description('Azure AD Client ID for JWT validation')
param clientId string

@description('Tags to apply to resources')
param tags object

// Variables
var appGwName = 'appgw-${applicationName}-${environmentName}-${uniqueSuffix}'
var publicIpName = 'pip-appgw-${applicationName}-${environmentName}-${uniqueSuffix}'
var wafPolicyName = 'waf-${applicationName}-${environmentName}-${uniqueSuffix}'

// Public IP for Application Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: '${applicationName}-${environmentName}-${uniqueSuffix}'
    }
  }
}

// WAF Policy
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-11-01' = {
  name: wafPolicyName
  location: location
  tags: tags
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Detection'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: appGwName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backendPool'
        properties: {
          backendAddresses: [
            {
              fqdn: backendFqdn
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'backendHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, 'healthProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port_80')
          }
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'routingRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'httpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'backendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'backendHttpSettings')
          }
        }
      }
    ]
    probes: [
      {
        name: 'healthProbe'
        properties: {
          protocol: 'Https'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    firewallPolicy: {
      id: wafPolicy.id
    }
  }
}

// Note: JWT validation in Application Gateway requires custom configuration
// that cannot be fully automated via Bicep. See documentation for manual steps.

// Outputs
output id string = applicationGateway.id
output name string = applicationGateway.name
output publicIpAddress string = publicIp.properties.ipAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
output configurationNotes string = '''
IMPORTANT: JWT Validation Configuration

Application Gateway has been deployed, but JWT validation requires additional manual configuration:

1. Application Gateway currently does not support native JWT validation
2. For JWT validation, you have these options:

   Option A - Container App Level Validation (RECOMMENDED):
   - The backend container app validates JWT tokens (already implemented)
   - Application Gateway passes through the Authorization header
   - This is the simplest and most flexible approach

   Option B - Custom WAF Rules:
   - Create custom WAF rules to inspect Authorization header
   - Limited validation capability compared to full JWT validation

   Option C - Azure API Management:
   - Add Azure API Management between App Gateway and Container App
   - APIM provides robust JWT validation policies

For this implementation, we are using Option A (container-level validation).
The Application Gateway will pass through all requests with Authorization headers
to the backend Container App which performs full JWT validation.

Backend FQDN: ${backendFqdn}
App Gateway Public IP: ${publicIp.properties.ipAddress}
App Gateway FQDN: ${publicIp.properties.dnsSettings.fqdn}

Access the API at: http://${publicIp.properties.dnsSettings.fqdn}/api/protected
'''
