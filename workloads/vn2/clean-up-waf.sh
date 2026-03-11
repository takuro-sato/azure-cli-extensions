#!/bin/bash
#
# One-off script to clean up WAF resources that were previously created by
# deploy-aks.sh / update-waf.sh.  These are no longer needed now that we
# use the AKS service's external IP directly.
#
# Usage: ./clean-up-waf.sh <AKS_RESOURCE_GROUP> <CLUSTER_NAME>

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <AKS_RESOURCE_GROUP> <CLUSTER_NAME>" >&2
    exit 1
fi

set -euo pipefail

AKS_RESOURCE_GROUP="$1"
CLUSTER_NAME="$2"

echo "Fetching AKS cluster info..."
aks_info="$(az aks show --resource-group "$AKS_RESOURCE_GROUP" --name "$CLUSTER_NAME" -o json)"
location=$(echo "$aks_info" | jq -r '.location')
mc_resource_group=$(echo "$aks_info" | jq -r '.nodeResourceGroup')

echo "AKS location: $location"
echo "MC resource group: $mc_resource_group"

WAF_NAME="vn2-aks-waf-$location"
PUBLIC_IP_NAME="vn2-waf-pub-ip-$location"
WAF_POLICY_NAME="wafp"
SUBNET_NAME="waf"

# Get the VNet name (needed for subnet and NSG cleanup)
VNET_NAME=$(az network vnet list --resource-group "$mc_resource_group" --query "[0].name" -o tsv)
NSG_NAME="${VNET_NAME}-waf-nsg"

echo ""
echo "Will delete the following resources in resource group '$mc_resource_group':"
echo "  Application Gateway: $WAF_NAME"
echo "  WAF Policy:          $WAF_POLICY_NAME"
echo "  Public IP:           $PUBLIC_IP_NAME"
echo "  Subnet:              $SUBNET_NAME (in VNet $VNET_NAME)"
echo "  NSG:                 $NSG_NAME"
echo ""

# 1. Delete the Application Gateway (must be deleted before public IP and subnet)
if az network application-gateway show --resource-group "$mc_resource_group" -n "$WAF_NAME" &>/dev/null; then
    echo "Deleting Application Gateway '$WAF_NAME'..."
    az network application-gateway delete --resource-group "$mc_resource_group" -n "$WAF_NAME"
    echo "  Deleted."
else
    echo "Application Gateway '$WAF_NAME' not found, skipping."
fi

# 2. Delete the WAF policy
if az network application-gateway waf-policy show --resource-group "$mc_resource_group" -n "$WAF_POLICY_NAME" &>/dev/null; then
    echo "Deleting WAF Policy '$WAF_POLICY_NAME'..."
    az network application-gateway waf-policy delete --resource-group "$mc_resource_group" -n "$WAF_POLICY_NAME"
    echo "  Deleted."
else
    echo "WAF Policy '$WAF_POLICY_NAME' not found, skipping."
fi

# 3. Delete the Public IP
if az network public-ip show --resource-group "$mc_resource_group" -n "$PUBLIC_IP_NAME" &>/dev/null; then
    echo "Deleting Public IP '$PUBLIC_IP_NAME'..."
    az network public-ip delete --resource-group "$mc_resource_group" -n "$PUBLIC_IP_NAME"
    echo "  Deleted."
else
    echo "Public IP '$PUBLIC_IP_NAME' not found, skipping."
fi

# 4. Delete the WAF subnet (must be deleted before the NSG)
if [[ -n "$VNET_NAME" ]] && az network vnet subnet show --resource-group "$mc_resource_group" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" &>/dev/null; then
    echo "Deleting subnet '$SUBNET_NAME' from VNet '$VNET_NAME'..."
    az network vnet subnet delete --resource-group "$mc_resource_group" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME"
    echo "  Deleted."
else
    echo "Subnet '$SUBNET_NAME' not found, skipping."
fi

# 5. Delete the NSG
if [[ -n "$VNET_NAME" ]] && az network nsg show --resource-group "$mc_resource_group" -n "$NSG_NAME" &>/dev/null; then
    echo "Deleting NSG '$NSG_NAME'..."
    az network nsg delete --resource-group "$mc_resource_group" -n "$NSG_NAME"
    echo "  Deleted."
else
    echo "NSG '$NSG_NAME' not found, skipping."
fi

echo ""
echo "WAF cleanup complete."
