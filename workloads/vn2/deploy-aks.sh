#!/bin/bash

# Prompt for user inputs
read -p "Enter the Resource Group name: " RESOURCE_GROUP
read -p "Enter the AKS Cluster name: " CLUSTER_NAME
read -p "Enter the location (e.g., eastus, westus): " LOCATION

# Variables (you can customize these)
NODE_COUNT=2                     # Number of nodes
SUBNET_NAME="cg"                  # Subnet name
SUBNET_PREFIX="10.225.0.0/24"     # Address range for the new subnet (starting from 10.225.0.0)
AKS_IDENTITY_SUFFIX="agentpool"   # Expected suffix of the AKS managed identity
ROLE="Contributor"                # Role to assign
NODE_VM_SIZE="Standard_DC4as_cc_v5"        # Node size for AKS cluster
MIN_COUNT=1                       # Minimum number of nodes (for autoscaler, Dev/Test)
MAX_COUNT=3                       # Maximum number of nodes (for autoscaler, Dev/Test)

# 1) Check and Create Resource Group if it doesn't exist
if az group show --name $RESOURCE_GROUP &>/dev/null; then
    echo "Resource group '$RESOURCE_GROUP' already exists. Moving to the next step..."
else
    echo "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
fi

# 2) Check if AKS Cluster exists and create if it doesn't
if az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME &>/dev/null; then
    echo "AKS cluster '$CLUSTER_NAME' already exists in resource group '$RESOURCE_GROUP'. Skipping creation."
else
    echo "Creating AKS cluster with Dev/Test preset..."
    az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --node-count $NODE_COUNT \
        --node-vm-size $NODE_VM_SIZE \
        --generate-ssh-keys \
        --location $LOCATION \
        --enable-managed-identity \
        --enable-cluster-autoscaler \
        --min-count $MIN_COUNT \
        --max-count $MAX_COUNT \
        --auto-upgrade-channel patch \
        --node-os-upgrade-channel NodeImage \
        --nodepool-labels "environment=devtest"
fi

# wait until the resource group can be queried
sleep 5

# Get the resource group name of the managed cluster (MC_* is the default resource group for AKS managed resources)
MC_RESOURCE_GROUP=$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query "nodeResourceGroup" -o tsv)
echo "Managed Cluster Resource Group: $MC_RESOURCE_GROUP"

# 3) Retrieve the VNet details
VNET_NAME=$(az network vnet list --resource-group $MC_RESOURCE_GROUP --query "[0].name" -o tsv)
VNET_ID=$(az network vnet show --resource-group $MC_RESOURCE_GROUP --name $VNET_NAME --query "id" -o tsv)
echo "Virtual Network: $VNET_NAME"

# 4) Create a Subnet within the VNet
echo "Creating subnet '$SUBNET_NAME' in VNet '$VNET_NAME'..."
az network vnet subnet create \
    --resource-group $MC_RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $SUBNET_NAME \
    --address-prefixes $SUBNET_PREFIX \
    --delegations "Microsoft.ContainerInstance/containerGroups"

# 5) Assign Contributor Role to AKS Managed Identity on MC Resource Group
# Find the managed identity (this identity will typically have a name that ends with "agentpool")
echo "Fetching AKS Managed Identity..."
AKS_MANAGED_IDENTITY_CLIENT_ID=$(az identity list --resource-group $MC_RESOURCE_GROUP --query "[?contains(name, '$AKS_IDENTITY_SUFFIX')].clientId" -o tsv)

# Assign Contributor role on the AKS resource group
echo "Assigning 'Contributor' role to Managed Identity '$AKS_MANAGED_IDENTITY_CLIENT_ID' on '$MC_RESOURCE_GROUP'..."
az role assignment create \
    --assignee $AKS_MANAGED_IDENTITY_CLIENT_ID \
    --role $ROLE \
    --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$MC_RESOURCE_GROUP

echo "AKS cluster deployment and subnet configuration completed."
