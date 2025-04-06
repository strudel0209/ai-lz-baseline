targetScope = 'resourceGroup'

/*
  Deploy subnets and NSGs
*/

//todo - add training and scoring subnets

@description('The resource group location')
param location string = resourceGroup().location

@description('Name of the existing virtual network (spoke) in this resource group.')
@minLength(1)
param existingSpokeVirtualNetworkName string

@description('Name of the existing Internet UDR in this resource group. This should be blank for VWAN deployments.')
param existingUdrForInternetTrafficName string = ''

@description('The IP range of the hub-provided Azure Bastion subnet range. Needed for workload to limit access in NSGs. For example, 10.0.1.0/26')
@minLength(9)
param bastionSubnetAddresses string

@description('Address space within the existing spoke\'s available address space to be used for Azure App Services.')
@minLength(9)
param appServicesSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for Azure Azure Application Gateway.')
@minLength(9)
param appGatewaySubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for the workload\'s private endpoints.')
@minLength(9)
param privateEndpointsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for build agents.')
@minLength(9)
param agentsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for jump boxes.')
@minLength(9)
param jumpBoxSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for AI Agents service.')
@minLength(9)
param aiAgentsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for AI Agents data plane.')
@minLength(9)
param aiAgentsDataPlaneSubnetAddressPrefix string

//--- Routing ----

// Hub firewall UDR
resource hubFirewallUdr 'Microsoft.Network/routeTables@2022-11-01' existing = if(existingUdrForInternetTrafficName != '') {
  name: existingUdrForInternetTrafficName
  scope: resourceGroup()
}

// ---- Networking resources ----


// Virtual network and subnets
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: existingSpokeVirtualNetworkName
  scope: resourceGroup()

  resource appServiceSubnet 'subnets' = {
    name: 'snet-appServicePlan'
    properties: {
      addressPrefix: appServicesSubnetAddressPrefix
      networkSecurityGroup: {
        id: appServiceSubnetNsg.id
      }
      delegations: [
        {
          name: 'delegation'
          properties: {
            serviceName: 'Microsoft.Web/serverFarms'
          }
        }
      ]
      routeTable: hubFirewallUdr != null
        ? {
            id: hubFirewallUdr.id
          }
        : null
    }
  }

  resource appGatewaySubnet 'subnets' = {
    name: 'snet-appGateway'
    properties: {
      addressPrefix: appGatewaySubnetAddressPrefix
      networkSecurityGroup: {
        id: appGatewaySubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'

      //routeTable: TODO for FW ingress
    }
    dependsOn: [
      appServiceSubnet // Single thread these
    ]
  }

  resource privateEndpointsSubnet 'subnets' = {
    name: 'snet-privateEndpoints'
    properties: {
      addressPrefix: privateEndpointsSubnetAddressPrefix
      networkSecurityGroup: {
        id: privateEndpointsSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      defaultOutboundAccess: false
      routeTable: hubFirewallUdr != null
        ? {
            id: hubFirewallUdr.id
          }
        : null
    }
    dependsOn: [
      appGatewaySubnet // Single thread these
    ]
  }

  resource agentsSubnet 'subnets' = {
    name: 'snet-agents'
    properties: {
      addressPrefix: agentsSubnetAddressPrefix
      networkSecurityGroup: {
        id: agentsSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      routeTable: hubFirewallUdr != null
        ? {
            id: hubFirewallUdr.id
          }
        : null
    }
    dependsOn: [
      privateEndpointsSubnet // Single thread these
    ]
  }

  resource jumpBoxSubnet 'subnets' = {
    name: 'snet-jumpbox'
    properties: {
      addressPrefix: jumpBoxSubnetAddressPrefix
      networkSecurityGroup: {
        id: jumpboxSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      routeTable: hubFirewallUdr != null
        ? {
            id: hubFirewallUdr.id
          }
        : null
    }
    dependsOn: [
      agentsSubnet // Single thread these
    ]
  }

  resource aiAgentsSubnet 'subnets' = {
    name: 'snet-aiagents'
    properties: {
      addressPrefix: aiAgentsSubnetAddressPrefix
      networkSecurityGroup: {
        id: aiAgentsSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      delegations: [
        {
          name: 'Microsoft.AzureAI.Agents'
          properties: {
            serviceName: 'Microsoft.AzureAI/Agents'
          }
        }
      ]
      routeTable: hubFirewallUdr != null
        ? {
            id: hubFirewallUdr.id
          }
        : null
    }
    dependsOn: [
      jumpBoxSubnet // Single thread these
    ]
  }

  resource aiAgentsDataPlaneSubnet 'subnets' = {
    name: 'snet-aiagents-dataplane'
    properties: {
      addressPrefix: aiAgentsDataPlaneSubnetAddressPrefix
      networkSecurityGroup: {
        id: aiAgentsDataPlaneSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      delegations: [
        {
          name: 'Microsoft.AzureAI.Agents.DataPlane'
          properties: {
            serviceName: 'Microsoft.AzureAI/Agents/DataPlane'
          }
        }
      ]
      routeTable: hubFirewallUdr != null
        ? {
            id: hubFirewallUdr.id
          }
        : null
    }
    dependsOn: [
      aiAgentsSubnet // Single thread these
    ]
  }
}

// App Gateway subnet NSG
resource appGatewaySubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-appGatewaySubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AppGw.In.Allow.ControlPlane'
        properties: {
          description: 'Allow inbound Control Plane (https://docs.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.In.Allow443.Internet'
        properties: {
          description: 'Allow ALL inbound web traffic on port 443'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: appGatewaySubnetAddressPrefix
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.In.Allow.LoadBalancer'
        properties: {
          description: 'Allow inbound traffic from azure load balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to the Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to Azure Monitor'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetAddressPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

// App Service subnet NSG
resource appServiceSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-appServicesSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AppPlan.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the app service subnet to the private endpoints subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: appServicesSubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from App service to the AzureMonitor ServiceTag.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appServicesSubnetAddressPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Private endpoints subnet NSG
resource privateEndpointsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-privateEndpointsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the private endpoints subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: privateEndpointsSubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Build agents subnet NSG
resource agentsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-agentsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the build agents subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: agentsSubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Jump box subnet NSG
resource jumpboxSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-jumpboxSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Jumpbox.In.Allow.SshRdp'
        properties: {
          description: 'Allow inbound RDP and SSH from the Bastion Host subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: bastionSubnetAddresses
          destinationPortRanges: [
            '22'
            '3389'
          ]
          destinationAddressPrefix: jumpBoxSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Jumpbox.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the jumpbox subnet to the Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpBoxSubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'Jumpbox.Out.Allow.Internet'
        properties: {
          description: 'Allow outbound traffic from all VMs to Internet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpBoxSubnetAddressPrefix
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpBoxSubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// AI Agents subnet NSG
resource aiAgentsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-aiAgentsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AIAgents.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the AI Agents subnet to the Private Endpoints subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: aiAgentsSubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AIAgents.Out.Allow.DataPlane'
        properties: {
          description: 'Allow outbound traffic from the AI Agents subnet to the AI Agents Data Plane subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: aiAgentsSubnetAddressPrefix
          destinationAddressPrefix: aiAgentsDataPlaneSubnetAddressPrefix
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AIAgents.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from AI Agents to the AzureMonitor ServiceTag'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: aiAgentsSubnetAddressPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
    ]
  }
}

// AI Agents Data Plane subnet NSG
resource aiAgentsDataPlaneSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-aiAgentsDataPlaneSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AIAgentsDataPlane.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the AI Agents Data Plane subnet to the Private Endpoints subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: aiAgentsDataPlaneSubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AIAgentsDataPlane.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from AI Agents Data Plane to the AzureMonitor ServiceTag'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: aiAgentsDataPlaneSubnetAddressPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

@description('The name of the spoke vnet.')
output vnetName string = vnet.name

@description('The name of the app service plan subnet.')
output appServicesSubnetName string = vnet::appServiceSubnet.name

@description('The name of the app gatewaysubnet.')
output appGatewaySubnetName string = vnet::appGatewaySubnet.name

@description('The name of the private endpoints subnet.')
output privateEndpointsSubnetName string = vnet::privateEndpointsSubnet.name

@description('The DNS servers that were configured on the virtual network.')
output vnetDNSServers array = contains(vnet.properties, 'dhcpOptions') && contains(vnet.properties.dhcpOptions, 'dnsServers') ? vnet.properties.dhcpOptions.dnsServers : []

@description('The name of the build agent subnet.')
output agentSubnetName string = vnet::agentsSubnet.name

@description('The name of the AI Agents subnet.')
output aiAgentsSubnetName string = vnet::aiAgentsSubnet.name

@description('The name of the AI Agents data plane subnet.')
output aiAgentsDataPlaneSubnetName string = vnet::aiAgentsDataPlaneSubnet.name
