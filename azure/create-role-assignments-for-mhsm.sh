#!/usr/bin/bash

if [ $# -eq 0 ]; then
    echo "No arguments provided. Please provide at least one region."
    exit 1
fi

if [ -z "$SUBSCRIPTION" ]; then
  echo "Environment variable SUBSCRIPTION is not set."
  exit 1
fi

if [ -z "$RESOURCE_GROUP" ]; then
  echo "Environment variable RESOURCE_GROUP is not set."
  exit 1
fi

regions=("$@")

for r in "${regions[@]}"; do
  for a in 'Managed HSM Crypto User' 'Managed HSM Crypto Officer'; do
    msi_id="/subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/cacidashboard-$r"
    az keyvault role assignment create --hsm-name cacisidecars --role "$a" --assignee-principal-type MSI \
      --assignee "$(az identity show --id "$msi_id" --query 'principalId' | jq -r)" \
      --scope '/';
  done;
done
