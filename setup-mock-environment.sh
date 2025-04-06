#!/bin/bash

# This script sets up a mock environment for the Azure OpenAI chat baseline landing zone
# Use this for development/testing when you don't have a full landing zone setup

echo "Setting up mock environment for Azure OpenAI Chat Baseline Landing Zone deployment"

# Set variables
LOCATION=${1:-eastus}
RESOURCE_GROUP="rg-chat-mock-prerequisites-${LOCATION}"
VNET_NAME="vnet-mock-spoke"
VNET_ADDRESS_PREFIX="10.1.0.0/16"
MOCK_UDR_NAME="udr-mock-to-hub"

# Create resource group for mock prerequisites
echo "Creating resource group for mock prerequisites"
az group create -l $LOCATION -n $RESOURCE_GROUP

# Create virtual network with DNS servers configured
echo "Creating virtual network with DNS servers"
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefix $VNET_ADDRESS_PREFIX \
  --subnet-name "default" \
  --subnet-prefix "10.1.0.0/24" \
  --dns-servers "168.63.129.16" ## Azure DNS

# Create mock UDR
echo "Creating mock UDR"
az network route-table create \
  --resource-group $RESOURCE_GROUP \
  --name $MOCK_UDR_NAME

# Add a default route to simulate routing through NVA
# This doesn't actually route through an NVA but serves as a placeholder
echo "Adding mock default route"
az network route-table route create \
  --resource-group $RESOURCE_GROUP \
  --route-table-name $MOCK_UDR_NAME \
  --name "DefaultRoute" \
  --address-prefix "0.0.0.0/0" \
  --next-hop-type "VirtualAppliance" \
  --next-hop-ip-address "10.1.0.4"

# Private DNS Zones section removed to avoid conflicts with the Bicep deployment

# Create a parameters file for the mock environment
echo "Creating mock parameters file"
cat > ./infra-as-code/bicep/parameters.mock.json << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "existingResourceIdForSpokeVirtualNetwork": {
      "value": "$(az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME --query id -o tsv)"
    },
    "existingResourceIdForUdrForInternetTraffic": {
      "value": "$(az network route-table show --resource-group $RESOURCE_GROUP --name $MOCK_UDR_NAME --query id -o tsv)"
    },
    "bastionSubnetAddresses": {
      "value": "10.1.3.0/26"
    },
    "appServicesSubnetAddressPrefix": {
      "value": "10.1.1.0/24"
    },
    "appGatewaySubnetAddressPrefix": {
      "value": "10.1.2.0/24"
    },
    "privateEndpointsSubnetAddressPrefix": {
      "value": "10.1.4.0/27"
    },
    "agentsSubnetAddressPrefix": {
      "value": "10.1.4.32/27"
    },
    "jumpBoxSubnetAddressPrefix": {
      "value": "10.1.4.128/28"
    },
    "aiAgentsSubnetAddressPrefix": {
      "value": "10.1.5.0/27"
    },
    "aiAgentsDataPlaneSubnetAddressPrefix": {
      "value": "10.1.5.32/27"
    }
  }
}
EOF

echo "Mock environment setup complete!"
echo "Use the following parameters file for deployment:"
echo "./infra-as-code/bicep/parameters.mock.json"
echo ""
echo "IMPORTANT: Update your deployment command to use this file:"
echo "az deployment sub create -f ./infra-as-code/bicep/main.bicep \\"
echo "  -n chat-baseline-mock \\"
echo "  -l $LOCATION \\"
echo "  -p @./infra-as-code/bicep/parameters.mock.json \\"
echo "  -p workloadResourceGroupName=\"rg-chat-alz-baseline-${LOCATION}\" \\"
echo "  -p appGatewayListenerCertificate=\${APP_GATEWAY_LISTENER_CERTIFICATE} \\"
echo "  -p baseName=\${BASE_NAME} \\"
echo "  -p yourPrincipalId=\${PRINCIPAL_ID}"