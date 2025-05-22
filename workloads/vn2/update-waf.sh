#!/bin/bash

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <AKS_RESOURCE_GROUP> <CLUSTER_NAME> <NODE_PORT|svc/SERVICE_NAME>" >&2
    exit 1
fi

set -euo pipefail

AKS_RESOURCE_GROUP="$1"
CLUSTER_NAME="$2"
NODE_PORT="$3"

cd "$(dirname "$0")"

aks_info="$(az aks show --resource-group "$AKS_RESOURCE_GROUP" --name "$CLUSTER_NAME" -o json)"
location=$(echo "$aks_info" | jq -r '.location')
mc_resource_group=$(echo "$aks_info" | jq -r '.nodeResourceGroup')
nodepool_name=$(echo "$aks_info" | jq -r '.agentPoolProfiles[0].name')
aks_machines="$(az aks machine list --resource-group "$AKS_RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" --nodepool-name "$nodepool_name" -o json)"
node_ips=(
    $(echo "$aks_machines" | jq -r '.[].properties.network.ipAddresses[0].ip')
)
if [[ ${#node_ips[@]} -eq 0 ]]; then
    echo "No node IPs found." >&2
    exit 1
fi
if [[ ${#node_ips[@]} -gt 1 ]]; then
    echo "Multiple node IPs found - not supported." >&2
    exit 1
fi
node_ip="${node_ips[0]}"
vnet_id=$(az network vnet list --resource-group "$mc_resource_group" --query "[0].id" -o tsv)

WAF_NAME="vn2-aks-waf-$location"

if [[ "$NODE_PORT" == svc/* ]]; then
    curr_ctx_name=$(kubectl config current-context)
    if [[ $curr_ctx_name != $CLUSTER_NAME ]]; then
        echo "Wrong kubectl context - expected to be $CLUSTER_NAME, but currently is $curr_ctx_name" >&2
        exit 1
    fi
    svc_name="${NODE_PORT#svc/}"
    svc_info="$(kubectl get svc "$svc_name" -o json)"
    if [[ -z "$svc_info" ]]; then
        echo "Service $svc_name not found." >&2
        exit 1
    fi
    NODE_PORT=$(echo "$svc_info" | jq -r '.spec.ports[0].nodePort')
    if [[ -z "$NODE_PORT" ]]; then
        echo "Node port not found for service $svc_name." >&2
        exit 1
    fi
fi

echo "Deploying/updating $WAF_NAME to point to $node_ip:$NODE_PORT" >&2

arm_params=(
    applicationGatewayName="$WAF_NAME"
    location="$location"
    publicIpAddressName="vn2-waf-pub-ip-$location"
    vnetId="$vnet_id"
    subnetName=waf
    backendAddress="$node_ip"
    backendPort="$NODE_PORT"
)

echo "ARM parameters:" >&2
for param in "${arm_params[@]}"; do
    echo "  - $param" >&2
done

deploy_out="$(az deployment group create \
            --name "$WAF_NAME-deployment" \
            --resource-group "$mc_resource_group" \
            --template-file appgw.json \
            --parameters "${arm_params[@]}")"

frontend_ip=$(echo "$deploy_out" | jq -r '.properties.outputs.frontendIP.value')

echo "WAF frontend IP: $frontend_ip"
echo "$frontend_ip" > ".waf-frontend-ip.txt"
