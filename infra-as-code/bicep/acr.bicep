targetScope = 'resourceGroup'

/*
  Deploy Azure Container Registry with private endpoint
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The name of the virtual network that this ACR instance will have a private endpoint in.')
param vnetName string

@description('The name of the resource group containing the spoke virtual network.')
@minLength(1)
param virtualNetworkResourceGroupName string

@description('The name of the subnet for the private endpoint. Must be in the provided virtual network.')
param privateEndpointsSubnetName string

@description('The name of the subnet for build agents. Must be in the provided virtual network.')
param buildAgentSubnetName string

@description('The name of the workload\'s existing Log Analytics workspace.')
param logWorkspaceName string

// Variables
var acrName = 'cr${baseName}'
var acrPrivateEndpointName = 'pep-${acrName}'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGroupName)

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }

  resource buildAgentSubnet 'subnets' existing = {
    name: buildAgentSubnetName
  }
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logWorkspaceName
}

@description('The container registry used by Azure AI Foundry to store Prompt flow images.')
resource acrResource 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'  // Changed from Premium to Standard for cost savings in PoC
  }
  properties: {
    adminUserEnabled: false
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices' // This allows support for ACR tasks to push the build image and bypass network restrictions - https://learn.microsoft.com/en-us/azure/container-registry/allow-access-trusted-services#trusted-services-workflow
    networkRuleSet: {
      defaultAction: 'Deny'
      ipRules: []
    }
    policies: {
      exportPolicy: {
        status: 'disabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'disabled'
      }
    }
    publicNetworkAccess: 'Disabled'
    // Removed zoneRedundancy property as it's only available in Premium SKU
  }
  // If this child resource fails or gets stuck in deployment then make sure your network settings, including DNS are correct. For reference https://learn.microsoft.com/azure/container-registry/tasks-agent-pools#add-firewall-rules
  // Removed agentPools resource as it requires Premium SKU
}

@description('Diagnostic settings for the Azure Container Registry instance.')
resource acrResourceDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: acrResource
  properties: {
    workspaceId: logWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs' // All logs is a good choice for production on this resource.
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    logAnalyticsDestinationType: null
  }
}

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: acrPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: acrPrivateEndpointName
        properties: {
          groupIds: [
            'registry'
          ]
          privateLinkServiceId: acrResource.id
        }
      }
    ]
  }
}

output acrName string = acrResource.name
