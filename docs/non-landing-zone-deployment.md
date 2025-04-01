# Deploying Azure OpenAI Chat Baseline in a Non-Landing Zone Environment

This guide helps you deploy the Azure OpenAI Chat Baseline solution when you don't have a fully-configured Azure Landing Zone, but do have a basic VNET in your subscription.

## Overview

The standard deployment assumes a well-structured landing zone with hub-spoke networking, DNS configuration, routing, and other enterprise components. This guide provides a simplified approach that:

1. Creates mock platform resources needed by the deployment
2. Adjusts parameters to work with these mock resources
3. Guides you through a streamlined deployment process

## Prerequisites

- Azure subscription with permissions to create resources
- Azure CLI installed
- Ability to create a VNET and subnets (if you don't already have one)
- Quota for Azure OpenAI and other required resources

## Step 1: Set Up the Mock Environment

We've created a script that sets up all the mock prerequisites needed to simulate a landing zone environment:

1. Make the script executable:
   ```bash
   chmod +x ./setup-mock-environment.sh
   ```

2. Run the script with your preferred Azure region:
   ```bash
   ./setup-mock-environment.sh eastus
   ```

This script:
- Creates a new resource group for mock prerequisites
- Deploys a VNET to represent your "spoke" network
- Creates a mock route table (UDR) to simulate NVA routing
- Creates all required private DNS zones and links them to your VNET
- Generates a parameters file specifically for this mock environment

## Step 2: Deploy the Solution

Follow the standard deployment steps from the README.md, with these adjustments:

1. Set your variables:
   ```bash
   LOCATION=eastus  # Use the same region you used in the mock setup
   BASE_NAME=<your-unique-name>  # 6-8 lowercase characters
   RESOURCE_GROUP="rg-chat-alz-baseline-${LOCATION}"
   ```

2. Generate the certificate (follow the standard steps in README.md)

3. Use the mock parameters file for deployment:
   ```bash
   PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

   az deployment sub create -f ./infra-as-code/bicep/main.bicep \
     -n chat-baseline-mock \
     -l $LOCATION \
     -p @./infra-as-code/bicep/parameters.mock.json \
     -p workloadResourceGroupName=${RESOURCE_GROUP} \
     -p appGatewayListenerCertificate=${APP_GATEWAY_LISTENER_CERTIFICATE} \
     -p baseName=${BASE_NAME} \
     -p yourPrincipalId=${PRINCIPAL_ID}
   ```

## Step 3: Complete the Deployment

Follow the remaining steps in the original README.md, starting from "Apply workaround for Azure AI Foundry not deploying its managed network."

## Important Differences

This mock environment differs from a true landing zone in these ways:

1. **No Hub Network**: There is no actual hub VNET with NVA for traffic inspection
2. **Direct Internet Access**: Traffic flows directly to the internet instead of through a firewall
3. **DNS Resolution**: Uses the mock private DNS zones without a central DNS resolver
4. **No Governance Controls**: Landing zone policies and compliance controls are not present

## Cleaning Up

To delete all resources, make sure to delete both resource groups:
```bash
az group delete --name $RESOURCE_GROUP -y
az group delete --name rg-chat-mock-prerequisites-${LOCATION} -y

az keyvault purge -n kv-${BASE_NAME}
az cognitiveservices account purge -g $RESOURCE_GROUP -l $LOCATION -n oai-${BASE_NAME}
```

## Transitioning to a Full Landing Zone

When you're ready to move to a production environment with a proper landing zone:
1. Update the parameters.alz.json with your actual landing zone values
2. Redeploy following the standard instructions