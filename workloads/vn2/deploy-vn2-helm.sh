#!/bin/bash
set -e

# Check if the correct number of arguments are provided
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <resource-group-name> <aks-cluster-name> [<namespace>]"
  exit 1
fi

RESOURCE_GROUP=$1
AKS_CLUSTER_NAME=$2
NAMESPACE=${3:-default}

. "$(dirname "$0")/isolate_kube_config.inc.sh"

# Set the AKS context for kubectl
echo "Setting the AKS context for kubectl..."
az aks get-credentials --overwrite-existing --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME"

# Switch to the specified namespace
kubectl config set-context --current --namespace="$NAMESPACE"

# Check if vn2 is already installed and install if not
if helm list --filter 'vn2' | grep -q 'vn2'; then
  echo "Helm release 'vn2' is already installed. Skipping Helm install."
else
  echo "Helm release 'vn2' is not installed. Proceeding with installation."
  if [[ ! -d "virtualnodesOnAzureContainerInstances/Helm" ]]; then
    echo "Cloning virtualnodesOnAzureContainerInstances..."
    git clone https://github.com/microsoft/virtualnodesOnAzureContainerInstances.git --depth 1 --single-branch --branch main
  fi

  # Use newer VN2 kubelet image if it's old
  sed -i 's/mcr\.microsoft\.com\/aci\/virtual-node-2-kubelet:main_20251023\.1/mcr.microsoft.com\/aci\/virtual-node-2-kubelet:kubelet_ubuntu_20251106.1/g' \
    workloads/vn2/virtualnodesOnAzureContainerInstances/Helm/virtualnode/values.yaml

  helm install vn2 virtualnodesOnAzureContainerInstances/Helm/virtualnode
fi
