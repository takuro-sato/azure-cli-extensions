#!/usr/bin/bash
#
# Populate peer IPs on all container groups via az container exec.
#
# Usage: populate_peers.sh <resource_group> <container_group_name_0> <ip_0> [<container_group_name_1> <ip_1> ...]
#
# This script expects pairs of (container_group_name, ip) after the resource group.

set -euo pipefail

RESOURCE_GROUP="$1"
shift

# Parse pairs of (name, ip)
declare -a NAMES=()
declare -a IPS=()

while [ $# -ge 2 ]; do
  NAMES+=("$1")
  IPS+=("$2")
  shift 2
done

ALL_IPS="${IPS[*]}"
echo "All IPs: $ALL_IPS"

has_error=0
for idx in "${!NAMES[@]}"; do
  name="${NAMES[$idx]}"
  self_ip="${IPS[$idx]}"
  echo "Populating peer IPs on $name (self=$self_ip)..."
  az container exec \
    --resource-group "$RESOURCE_GROUP" \
    --name "$name" \
    --container-name net-liveness \
    --exec-command "python3 /populate_peer_ips.py $ALL_IPS --self-ip $self_ip"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to populate peer IPs on $name"
    has_error=1
  fi
done

if [ $has_error -ne 0 ]; then
  echo "ERROR: Failed to populate peer IPs on one or more container groups"
  exit 1
fi
echo "All peer IPs populated successfully."
