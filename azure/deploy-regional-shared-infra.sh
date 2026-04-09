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

cd "$(dirname "$0")" || exit 1

set -ex
for r in "${regions[@]}"; do
  az deployment group create \
    -n "regional-shared-infra-$r" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file regional-shared.bicep \
    --parameters location="$r"
done
