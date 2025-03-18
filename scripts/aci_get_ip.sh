#!/usr/bin/bash

if [ -z "$DEPLOYMENT_NAME" ]; then
  echo "DEPLOYMENT_NAME is not set"
  exit 1
fi
if [ -z "$RESOURCE_GROUP" ]; then
  echo "RESOURCE_GROUP is not set"
  exit 1
fi

cd "$(dirname "$0")"
./tracing/trace_step.py --start 'Wait for IP address'
ip_address=""
elapsed=0
while [[ -z "$ip_address" && elapsed -lt 60 ]]; do
  ip_address=$(c-aci-testing aci get ips --deployment-name $DEPLOYMENT_NAME | sed "s/\['\([^']*\)'\]/\1/")
  echo "IP Address: $ip_address"
  sleep 5
  elapsed=$((elapsed + 5))
done

if [ -z "$ip_address" ]; then
  echo "Failed to get IP address from c-aci-testing"

  # Try directly getting it from az-cli instead (this is what server workload used to do)
  ip_address="$(\
    az container show \
    --resource-group $RESOURCE_GROUP \
    --name $DEPLOYMENT_NAME \
    --query ipAddress.ip --output tsv \
  )"
  status=$?

  if [ "$status" -ne 0 ] || [ -z "$ip_address" ]; then
    echo "Failed to get IP address from az-cli"
    ./tracing/trace_step.py --complete --strict --err "Failed to get IP address"
    exit 1
  fi
fi

./tracing/trace_step.py --complete --output "ip_address=$ip_address"

if [ -n "$GITHUB_ENV" ]; then
  echo "ip_address=$ip_address" >> $GITHUB_ENV
  echo "ip_address=$ip_address >> \$GITHUB_ENV"
else
  echo "$ip_address"
fi
