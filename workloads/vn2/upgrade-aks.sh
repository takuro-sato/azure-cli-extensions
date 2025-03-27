#!/bin/bash

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <RESOURCE_GROUP> <CLUSTER_NAME>"
    exit 1
fi

set -e

RESOURCE_GROUP=$1
CLUSTER_NAME=$2

nodes=$(az aks nodepool list -g vn2-aks-eastus --cluster-name vn2-aks-eastus --query '[].name' -o tsv)
for node in $nodes; do
    echo "upgrading nodepool $node"
    az aks nodepool upgrade \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $CLUSTER_NAME \
        --name $node \
        --yes \
        --max-surge '100%'
    az aks nodepool upgrade \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $CLUSTER_NAME \
        --name $node \
        --yes \
        --node-image-only
done
