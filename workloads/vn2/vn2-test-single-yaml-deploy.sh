#!/usr/bin/bash

set -o pipefail

if [ -z "$MONITOR_SECS" ]; then
  MONITOR_SECS=300
fi

TEST_YAML="$1"
if [ -z "$TEST_YAML" ]; then
  echo "Usage: $0 <test-yaml>"
  exit 1
fi

TEST_YAML="$(realpath "$TEST_YAML")"

cd "$(dirname "$0")"
TRACE_SCRIPT="$(realpath ../../scripts/tracing/trace_step.py)"

$TRACE_SCRIPT --start "vn2 deploy $TEST_YAML"
rm -f vn2deploy.log
c-aci-testing vn2 deploy "$(dirname $TEST_YAML)" --yaml-path $TEST_YAML --monitor-duration-secs $MONITOR_SECS --deploy-output-file test_output.json 2>&1 | tee vn2deploy.log
status=$?
cat test_output.json
if [ $? -ne 0 ]; then
  echo "Failed to read test_output.json"
  $TRACE_SCRIPT --complete --strict --err "$(cat vn2deploy.log)
Failed to read test_output.json"
  exit 1
fi
if [ $status -ne 0 ]; then
  cat test_output.json | $TRACE_SCRIPT --complete --strict --output-from-stdin --err "$(cat test_output.json | jq -r '.err_str')"
  exit 1
else
  cat test_output.json | $TRACE_SCRIPT --complete --strict --output-from-stdin
  exit $?
fi
