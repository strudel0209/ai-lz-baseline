targetScope = 'resourceGroup'

/*
  Deploy Azure AI Agent Service with private networking
*/

@description('The resource group location')
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('The name of the resource group containing the spoke virtual network.')
@minLength(1)
param virtualNetworkResourceGroupName string

// existing resource name params
param vnetName string
param privateEndpointsSubnetName string
param aiAgentsSubnetName string
param aiAgentsDataPlaneSubnetName string
param logWorkspaceName string
param keyVaultName string
param storageAccountName string
param openAiResourceName string
param aiSearchName string

@description('The name of the user-assigned managed identity for AI Agents')
param agentsManagedIdentityName string = 'id-aiagents-${baseName}'

@maxLength(37)
@minLength(36)
param yourPrincipalId string

// ---- Variables ----
var aiAgentsProjectName = 'aiproj-agents-${baseName}'
var aiAgentsDnsZoneName = 'privatelink.cognitiveservices.azure.com'
var aiAgentsPrivateEndpointName = 'pep-${aiAgentsProjectName}'
var aiAgentsDnsGroupName = '${aiAgentsPrivateEndpointName}/default'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGroupName)

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }

  resource aiAgentsSubnet 'subnets' existing = {
    name: aiAgentsSubnetName
  }

  resource aiAgentsDataPlaneSubnet 'subnets' existing = {
    name: aiAgentsDataPlaneSubnetName
  }
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logWorkspaceName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: openAiResourceName
}

resource aiSearchAccount 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
}

@description('Built-in Role: [Storage Blob Data Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor)')
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

@description('Built-in Role: [Cognitive Services OpenAI User](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#cognitive-services-openai-user)')
resource cognitiveServicesOpenAiUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  scope: subscription()
}

@description('Built-in Role: [Search Service Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#search-service-contributor)')
resource searchServiceContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  scope: subscription()
}

@description('Built-in Role: [Search Index Data Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#search-index-data-contributor)')
resource searchIndexDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  scope: subscription()
}

@description('Built-in Role: [Azure AI Developer](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#azure-ai-developer)')
resource azureAiDeveloperRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '186d5d51-cfdd-45ca-ac9a-39d5aa9c410a'
  scope: subscription()
}

// ---- New Resources ----

// Create user-assigned managed identity for AI Agents
resource agentsManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: agentsManagedIdentityName
  location: location
}

// AI Agents project resource with private networking
resource aiAgentsProject 'Microsoft.AzureAI/projects@2023-05-01' = {
  name: aiAgentsProjectName
  location: location
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${agentsManagedIdentity.id}': {}
    }
  }
  properties: {
    owner: yourPrincipalId
    publicNetworkAccess: 'Disabled'
    storage: {
      storageId: storageAccount.id
    }
    searchService: {
      searchServiceId: aiSearchAccount.id
    }
    network: {
      subnetId: vnet::aiAgentsSubnet.id
      dataplaneSubnetId: vnet::aiAgentsDataPlaneSubnet.id
    }
  }
}

// Role assignments for the managed identity
resource openAiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, agentsManagedIdentity.id, cognitiveServicesOpenAiUserRole.id)
  scope: openAiAccount
  properties: {
    roleDefinitionId: cognitiveServicesOpenAiUserRole.id
    principalType: 'ServicePrincipal'
    principalId: agentsManagedIdentity.properties.principalId
  }
}

resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, agentsManagedIdentity.id, storageBlobDataContributorRole.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRole.id
    principalType: 'ServicePrincipal' 
    principalId: agentsManagedIdentity.properties.principalId
  }
}

resource searchServiceContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearchAccount.id, agentsManagedIdentity.id, searchServiceContributorRole.id)
  scope: aiSearchAccount
  properties: {
    roleDefinitionId: searchServiceContributorRole.id
    principalType: 'ServicePrincipal'
    principalId: agentsManagedIdentity.properties.principalId
  }
}

resource searchIndexDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearchAccount.id, agentsManagedIdentity.id, searchIndexDataContributorRole.id)
  scope: aiSearchAccount
  properties: {
    roleDefinitionId: searchIndexDataContributorRole.id
    principalType: 'ServicePrincipal'
    principalId: agentsManagedIdentity.properties.principalId
  }
}

// Role assignment for your user to manage the AI Agents project
resource azureAiDeveloperRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiAgentsProject.id, yourPrincipalId, azureAiDeveloperRole.id)
  scope: aiAgentsProject
  properties: {
    roleDefinitionId: azureAiDeveloperRole.id
    principalType: 'User'
    principalId: yourPrincipalId
  }
}

// Create private endpoint for AI Agents 
resource aiAgentsPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: aiAgentsPrivateEndpointName
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: aiAgentsPrivateEndpointName
        properties: {
          groupIds: [
            'account'
          ]
          privateLinkServiceId: aiAgentsProject.id
        }
      }
    ]
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
  }
}

// Create Private DNS Zone for AI Agents
resource aiAgentsDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: aiAgentsDnsZoneName
  location: 'global'
  properties: {}
}

// Create Virtual Network Link for AI Agents DNS Zone
resource aiAgentsDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aiAgentsDnsZone
  name: '${aiAgentsDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Configure DNS Zone Group for the AI Agents private endpoint
resource aiAgentsDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  name: aiAgentsDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'aiagents-config'
        properties: {
          privateDnsZoneId: aiAgentsDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    aiAgentsPrivateEndpoint
  ]
}

@description('Azure Diagnostics: AI Agents Project - allLogs')
resource aiAgentsProjectDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: aiAgentsProject
  properties: {
    workspaceId: logWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

output aiAgentsProjectId string = aiAgentsProject.id
output aiAgentsProjectName string = aiAgentsProject.name
output agentsManagedIdentityId string = agentsManagedIdentity.id
