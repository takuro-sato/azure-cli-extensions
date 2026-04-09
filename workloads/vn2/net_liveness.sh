#!/usr/bin/bash
#
# VN2 net-liveness test.
#
# Deploys multiple replicas of the net-liveness container, discovers pod IPs
# via kubectl, populates peer lists, waits, then collects output and stats.
#
# Environment variables:
#   CONTAINER_GROUP_COUNT - number of replicas (default: 2)
#   MONITOR_SECS          - how long to let heartbeats run (default: 600)
#   CLEANUP               - set to 'false' to skip cleanup

set -euo pipefail

CONTAINER_GROUP_COUNT="${CONTAINER_GROUP_COUNT:-2}"
MONITOR_SECS="${MONITOR_SECS:-600}"

SCRIPTS_DIR="$(realpath "$(dirname "$0")/../../scripts")"
WORKLOAD_DIR="$(realpath "$(dirname "$0")/../net_liveness")"
TRACE_SCRIPT="$SCRIPTS_DIR/tracing/trace_step.py"

cd workloads/net_liveness

# Pull images and generate YAML/policy
$TRACE_SCRIPT --start 'Pull image'
c-aci-testing images pull .
if [ $? -ne 0 ]; then
  $TRACE_SCRIPT --complete --strict --err "Failed to pull images"
  exit 1
fi

$TRACE_SCRIPT --start 'vn2 generate_yaml'
c-aci-testing vn2 generate_yaml . --replicas $CONTAINER_GROUP_COUNT --ignore-vnets
if [ $? -ne 0 ]; then
  $TRACE_SCRIPT --complete --strict --err "Failed to generate YAML"
  exit 1
fi

echo
echo "Generated YAML file:"
cat net_liveness.yaml
echo

$TRACE_SCRIPT --start 'vn2 policygen'
c-aci-testing vn2 policygen .
if [ $? -ne 0 ]; then
  $TRACE_SCRIPT --complete --strict --err "Failed to generate policy"
  exit 1
fi

echo
echo "Generated YAML with policy:"
cat net_liveness.yaml
echo

# Deploy
MONITOR_SECS=20 ../../workloads/vn2/vn2-test-single-yaml-deploy.sh net_liveness.yaml
if [ $? -ne 0 ]; then
  echo "Failed to deploy"
  exit 1
fi

# Discover pod IPs
$TRACE_SCRIPT --start 'Discover pod IPs and populate peers'

# Extract the label selector from the generated YAML
APP_LABEL=$(grep -A1 'app:' net_liveness.yaml | head -1 | awk '{print $NF}')
echo "Using app label: $APP_LABEL"

set +e
attempts=0
while [ $attempts -lt 30 ]; do
  POD_IPS=$(kubectl get pods -l "app=$APP_LABEL" -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | grep -v '^$')
  POD_COUNT=$(echo "$POD_IPS" | wc -l)
  if [ "$POD_COUNT" -ge "$CONTAINER_GROUP_COUNT" ]; then
    break
  fi
  echo "Waiting for pods to get IPs (have $POD_COUNT, want $CONTAINER_GROUP_COUNT)..."
  sleep 5
  attempts=$((attempts + 1))
done
set -e

if [ "$POD_COUNT" -lt "$CONTAINER_GROUP_COUNT" ]; then
  $TRACE_SCRIPT --complete --strict --err "Only $POD_COUNT pods have IPs, expected $CONTAINER_GROUP_COUNT"
  exit 1
fi

echo "Pod IPs: $POD_IPS"
ALL_IPS=$(echo "$POD_IPS" | tr '\n' ' ')

# Get pod names
POD_NAMES=$(kubectl get pods -l "app=$APP_LABEL" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -v '^$')
readarray -t POD_NAME_ARR <<< "$POD_NAMES"
readarray -t POD_IP_ARR <<< "$POD_IPS"

# Populate peer IPs on each pod
has_error=0
for idx in "${!POD_NAME_ARR[@]}"; do
  pod="${POD_NAME_ARR[$idx]}"
  self_ip="${POD_IP_ARR[$idx]}"
  echo "Populating peers on pod $pod (self=$self_ip)..."
  kubectl exec "$pod" -c net-liveness -- python3 /populate_peer_ips.py $ALL_IPS --self-ip "$self_ip"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to populate peers on $pod"
    has_error=1
  fi
done

if [ $has_error -ne 0 ]; then
  $TRACE_SCRIPT --complete --strict --err "Failed to populate peers on one or more pods"
  exit 1
fi
$TRACE_SCRIPT --complete --strict

# Wait for heartbeats
echo "Waiting ${MONITOR_SECS}s for heartbeat exchange..."
sleep "$MONITOR_SECS"

# Collect logs
has_error=0
for idx in "${!POD_NAME_ARR[@]}"; do
  pod="${POD_NAME_ARR[$idx]}"
  kubectl logs "$pod" -c net-liveness > "output-${idx}.log" 2>&1 || ( has_error=1; echo "ERROR: Failed to get logs from $pod" )
  cat "output-${idx}.log"

  echo "===== Parse output $pod ====="
  $SCRIPTS_DIR/parse_container_output.py --fail-on-error "output-${idx}.log" || has_error=1
done

# Collect stats (regardless of errors above)
$TRACE_SCRIPT --start 'Aggregate net-liveness stats'
echo "===== Collecting stats ====="
for idx in "${!POD_NAME_ARR[@]}"; do
  pod="${POD_NAME_ARR[$idx]}"
  echo "===== Stats from $pod ====="
  kubectl exec "$pod" -c net-liveness -- python3 /get_stats.py | tee "stats-${idx}.log" || echo "WARNING: Failed to get stats from $pod"
  echo
done

# Aggregate and trace to Kusto
stat_files=()
for idx in "${!POD_NAME_ARR[@]}"; do
  stat_files+=("stats-${idx}.log")
done
python3 "$WORKLOAD_DIR/aggregate_stats.py" "${stat_files[@]}" || \
  $TRACE_SCRIPT --complete --err "Failed to aggregate stats"

if [ "$CLEANUP" != "false" ]; then
  c-aci-testing vn2 remove
fi

if [ $has_error -ne 0 ]; then
  exit 1
fi
