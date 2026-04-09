#!/bin/bash
set -exo pipefail

YAML_FILE=$1
STATEFULSET_NAME=$2

if [ -z "$YAML_FILE" ] || [ -z "$STATEFULSET_NAME" ]; then
  echo "Usage: $0 <yaml-file> <statefulset-name>"
  exit 1
fi

SCRIPTS_DIR=$(cd "$(dirname "$0")/../../scripts" && pwd)
POD_NAME="${STATEFULSET_NAME}-0"
LOG_FILE="output-${STATEFULSET_NAME}.log"

cleanup() {
  kubectl delete statefulset "$STATEFULSET_NAME" --ignore-not-found
}

"$SCRIPTS_DIR/tracing/trace_step.py" --start "Deploy $STEP_PREFIX"
kubectl apply -f "$YAML_FILE"
echo "Waiting for pod $POD_NAME to be ready..."
sleep 20
kubectl wait --for=condition=ready "pod/$POD_NAME" --timeout=300s

echo "Wait for 5 minutes"
sleep 300

"$SCRIPTS_DIR/tracing/trace_step.py" --start "Monitor $STEP_PREFIX"
timeout 120 kubectl logs -f "pod/$POD_NAME" -c primary > "$LOG_FILE" 2>&1 || true
cat "$LOG_FILE"

"$SCRIPTS_DIR/parse_container_output.py" --must-have-output "$LOG_FILE"

cleanup
