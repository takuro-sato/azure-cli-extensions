#!/bin/bash

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <RESOURCE_GROUP> <CLUSTER_NAME> <LOCATION>"
    exit 1
fi

RESOURCE_GROUP=$1
CLUSTER_NAME=$2
LOCATION=$3

# Variables (you can customize these)
NODE_COUNT=1                      # Number of nodes
SUBNET_NAME="cg"                  # Subnet name
SUBNET_PREFIX="10.225.0.0/24"     # Address range for the new subnet (starting from 10.225.0.0)
AKS_IDENTITY_SUFFIX="agentpool"   # Expected suffix of the AKS managed identity
ROLE="Contributor"                # Role to assign
NODE_VM_SIZE="Standard_D4as_v5"   # Node size for AKS cluster
MIN_COUNT=1                       # Minimum number of nodes (for autoscaler, Dev/Test)
MAX_COUNT=3                       # Maximum number of nodes (for autoscaler, Dev/Test)

RUNNER_IDENTITY_RESOURCE_GROUP="c-aci-dashboard"
RUNNER_IDENTITY_NAME="cacidashboard"

RUNNER_CLIENT_ID="$(az identity show --resource-group "$RUNNER_IDENTITY_RESOURCE_GROUP" -n "$RUNNER_IDENTITY_NAME" --query 'clientId' -o tsv)"

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
        --nodepool-labels "environment=devtest" \
        --os-sku AzureLinux
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
if az network vnet subnet show --resource-group $MC_RESOURCE_GROUP --vnet-name $VNET_NAME --name $SUBNET_NAME &>/dev/null; then
    echo "Subnet '$SUBNET_NAME' already exists in VNet '$VNET_NAME'. Skipping creation."
else
    echo "Creating subnet '$SUBNET_NAME' in VNet '$VNET_NAME'..."
    az network vnet subnet create \
        --resource-group $MC_RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name $SUBNET_NAME \
        --address-prefixes $SUBNET_PREFIX \
        --delegations "Microsoft.ContainerInstance/containerGroups"
fi

# 5) Assign Contributor Role to AKS Managed Identity on MC Resource Group
# Find the managed identity (this identity will typically have a name that ends with "agentpool")
echo "Fetching AKS Managed Identity..."
AKS_MANAGED_IDENTITY_CLIENT_ID=$(az identity list --resource-group $MC_RESOURCE_GROUP --query "[?contains(name, '$AKS_IDENTITY_SUFFIX')].clientId" -o tsv)
if [[ -z "$AKS_MANAGED_IDENTITY_CLIENT_ID" ]]; then
    echo "Error: Managed Identity not found. Please check the AKS cluster and try again."
    exit 1
fi

# Note: `az role assignment create` is idempotent, so we don't check if the role assignment already exists

# Assign Contributor role on the AKS resource group
SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$MC_RESOURCE_GROUP"
echo "Assigning 'Contributor' role to Managed Identity '$AKS_MANAGED_IDENTITY_CLIENT_ID' on '$MC_RESOURCE_GROUP'..."
az role assignment create \
    --assignee $AKS_MANAGED_IDENTITY_CLIENT_ID \
    --role $ROLE \
    --scope "$SCOPE"

# Allow runner access to the AKS itself
SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP"
echo "Assigning 'Contributor' role to Managed Identity '$RUNNER_CLIENT_ID' on '$RESOURCE_GROUP'..."
az role assignment create \
    --assignee $RUNNER_CLIENT_ID \
    --role $ROLE \
    --scope "$SCOPE"

echo "AKS cluster deployment and subnet configuration completed."
