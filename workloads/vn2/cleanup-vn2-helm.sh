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

# Set the AKS context for kubectl
echo "Setting the AKS context for kubectl..."
az aks get-credentials --overwrite-existing --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME"

# Switch to the specified namespace
kubectl config set-context --current --namespace="$NAMESPACE"

# Check if vn2 is already installed and return if not.
if ! helm list --filter 'vn2' | grep -q 'vn2'; then
  echo "Helm release 'vn2' is not installed. Skipping uninstall."
  exit 0
fi

echo "Starting cleanup of deployment and VN2 Helm chart..."

# Step 1: Delete all existing deployments/services
kubectl delete deployment --all --namespace="$NAMESPACE"
kubectl delete statefulset --all --namespace="$NAMESPACE"
kubectl delete pod --all --namespace="$NAMESPACE"
kubectl delete pvc --all
kubectl delete pv --all
kubectl get services -o name | grep -vE '^service/kubernetes$' | xargs --no-run-if-empty kubectl delete

# Step 2: Wait for pods to be deleted with a timeout of 8 minutes
echo "Waiting for pods to be deleted (timeout in 8 minutes)..."
end=$((SECONDS+480))  # 8 minutes timeout
while [ $SECONDS -lt $end ]; do
  if ! kubectl get pods --namespace="$NAMESPACE" | grep -q 'Running\|Pending\|ContainerCreating\|Terminating'; then
    echo "All pods are deleted."
    echo "Uninstalling Helm release 'vn2'..."
    if ! helm uninstall vn2; then
      # From past runs it seems like this can fail with:
      # Error: uninstallation completed with 1 error(s): uninstall: Failed to purge the release: release: not found
      # But the vn2 virtual node is deleted and no resources left in `kubectl get all`
      # So it's a bit weird.
      echo "Ignoring helm uninstall error."
    fi

    if kubectl get node vn2-virtualnode-0 > /dev/null 2>&1; then
      echo "Deleting the virtual node 'vn2-virtualnode-0'..."
      kubectl delete node vn2-virtualnode-0
    else
      echo "Virtual node 'vn2-virtualnode-0' not found. Skipping deletion."
    fi

    echo "Cleanup complete."
    exit 0
  fi
  echo "Pods are still terminating. Waiting for them to be deleted..."
  sleep 5
done

echo "Timeout reached. Pods did not delete within 8 minutes."
exit 1  # Exit immediately with failure if timeout occurs
