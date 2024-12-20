#!/usr/bin/env bash

set +e

./scripts/tracing/trace_step.py --start 'Get Container States'

az container show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" > /tmp/container_states.json

if [ $? -ne 0 ]; then
  echo "Failed to get container states"
  ./scripts/tracing/trace_step.py --complete --err 'Failed to get container states'
  exit 1
fi

cat /tmp/container_states.json | ./scripts/tracing/trace_step.py --complete --output-from-stdin

cat /tmp/container_states.json | jq -c '.containers[]' | while read -r container; do
  container_name=$(echo "$container" | jq -r '.name')
  echo "Events for container $container_name:"
  echo "$container" | jq -r '.instanceView | .events[]'
done
