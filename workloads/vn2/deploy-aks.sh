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
NODE_VM_SIZES_TO_TRY=(
    "Standard_DC4as_cc_v6"
    "Standard_DC2as_cc_v6"
    "Standard_DC4as_cc_v5"
    "Standard_DC2as_cc_v5"
    "Standard_DC8as_cc_v6"
    "Standard_DC8as_cc_v5"

    "Standard_EC4as_cc_v6"
    "Standard_EC2as_cc_v6"
    "Standard_EC4as_cc_v5"
    "Standard_EC2as_cc_v5"
    "Standard_EC8as_cc_v6"
    "Standard_EC8as_cc_v5"

    "Standard_D4as_v5"
    "Standard_D4as_v6"
    "Standard_D2as_v5"
    "Standard_D2as_v6"
    "Standard_D4s_v5"
    "Standard_D4s_v6"
    "Standard_D2s_v5"
    "Standard_D2s_v6"

    "Standard_E4s_v5"
    "Standard_E4s_v6"
    "Standard_E2s_v5"
    "Standard_E2s_v6"
)
MIN_COUNT=1                       # Minimum number of nodes (for autoscaler, Dev/Test)
MAX_COUNT=3                       # Maximum number of nodes (for autoscaler, Dev/Test)

RUNNER_IDENTITY_RESOURCE_GROUP="c-aci-dashboard"
RUNNER_IDENTITY_NAME="cacidashboard"

RUNNER_CLIENT_ID="$(az identity show --resource-group "$RUNNER_IDENTITY_RESOURCE_GROUP" -n "$RUNNER_IDENTITY_NAME" --query 'clientId' -o tsv)"

REGIONAL_IDENTITY_NAME="$RUNNER_IDENTITY_NAME-$LOCATION"
# REGIONAL_IDENTITY_CLIENT_ID="$(az identity show --resource-group "$RUNNER_IDENTITY_RESOURCE_GROUP" -n "$REGIONAL_IDENTITY_NAME" --query 'clientId' -o tsv)"

. "$(dirname "$0")/isolate_kube_config.inc.sh"

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
    success=0
    for vm_sku in "${NODE_VM_SIZES_TO_TRY[@]}"; do
        echo "Creating AKS cluster with $vm_sku..."
        az aks create \
            --resource-group $RESOURCE_GROUP \
            --name $CLUSTER_NAME \
            --node-count $NODE_COUNT \
            --node-vm-size $vm_sku \
            --generate-ssh-keys \
            --location $LOCATION \
            --enable-managed-identity \
            --enable-cluster-autoscaler \
            --min-count $MIN_COUNT \
            --max-count $MAX_COUNT \
            --auto-upgrade-channel patch \
            --node-os-upgrade-channel NodeImage \
            --nodepool-name "vn2np" \
            --nodepool-labels "environment=devtest" \
            --os-sku AzureLinux
        if [[ $? -eq 0 ]]; then
            echo "AKS cluster '$CLUSTER_NAME' created successfully with $vm_sku."
            success=1
            break
        else
            echo "Failed to create AKS cluster with $vm_sku. Trying next VM size..."
        fi
    done
    if [[ $success -ne 1 ]]; then
        echo "Error: Failed to create AKS cluster with all tried VM sizes."
        exit 1
    fi
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
# ...as well as the MC resource group
SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$MC_RESOURCE_GROUP"
echo "Assigning 'Contributor' role to Managed Identity '$RUNNER_CLIENT_ID' on '$MC_RESOURCE_GROUP'..."
az role assignment create \
    --assignee $RUNNER_CLIENT_ID \
    --role $ROLE \
    --scope "$SCOPE"

# Allow the AKS identity to have Managed Identity Operator on the cacidashboard-${region} identity so that we can test VN2 managed identity containers
SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RUNNER_IDENTITY_RESOURCE_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$REGIONAL_IDENTITY_NAME"
echo "Assigning 'Managed Identity Operator' role to Managed Identity '$AKS_MANAGED_IDENTITY_CLIENT_ID' on '$REGIONAL_IDENTITY_NAME'..."
az role assignment create \
    --assignee $AKS_MANAGED_IDENTITY_CLIENT_ID \
    --role "Managed Identity Operator" \
    --scope "$SCOPE"

echo "Getting AKS credentials..."
echo az aks get-credentials --overwrite-existing --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"
az aks get-credentials --overwrite-existing --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"
if [[ $? -ne 0 ]]; then
    echo "Failed to get AKS credentials."
    exit 1
fi

echo "AKS cluster deployment and subnet configuration completed."
