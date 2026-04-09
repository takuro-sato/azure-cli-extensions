#!/usr/bin/bash
#
# Collect stats from all container groups via az container exec.
# Saves each output to stats-<name>.log for later aggregation.
#
# Usage: collect_stats.sh <resource_group> <container_group_name_0> [<container_group_name_1> ...]

set -uo pipefail

RESOURCE_GROUP="$1"
shift

for name in "$@"; do
  echo "===== Stats from $name ====="
  az container exec \
    --resource-group "$RESOURCE_GROUP" \
    --name "$name" \
    --container-name net-liveness \
    --exec-command "python3 /get_stats.py" | tee "stats-${name}.log" || echo "WARNING: Failed to get stats from $name"
  echo
done
