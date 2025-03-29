#!/bin/bash

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <resource-group-name> <aks-cluster-name>"
  exit 1
fi

RESOURCE_GROUP=$1
AKS_CLUSTER_NAME=$2

if ! az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" > /dev/null 2>&1; then
  echo "AKS cluster '$AKS_CLUSTER_NAME' in resource group '$RESOURCE_GROUP' does not exist. Exiting..."
  exit 0
fi

echo "Deleting AKS cluster '$AKS_CLUSTER_NAME' in resource group '$RESOURCE_GROUP'..."

az aks delete --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --yes
