#!/usr/bin/bash

set -o pipefail

TRACE_SCRIPT="$(realpath "$(dirname "$0")/../../scripts/tracing/trace_step.py")" || exit 1
OUTPUT_DIR="$(realpath .)" || exit 1

DIR_NAME="${1:-.}"
cd "$DIR_NAME" || exit 1

export MONITOR_SECS="${MONITOR_SECS:-20}"

yaml_file="$(basename $PWD).yaml"

function err_die() {
  echo "$1"
  $TRACE_SCRIPT --complete --strict --err "$1"
  exit 1
}

$TRACE_SCRIPT --start 'Pull image'
c-aci-testing images pull .
if [ $? -ne 0 ]; then
  err_die "Failed to pull images"
fi
$TRACE_SCRIPT --start 'vn2 generate_yaml'
c-aci-testing vn2 generate_yaml .
if [ $? -ne 0 ]; then
  err_die "Failed to generate YAML"
fi
$TRACE_SCRIPT --start 'vn2 policygen'
c-aci-testing vn2 policygen .
if [ $? -ne 0 ]; then
  err_die "Failed to generate policy"
fi
echo
echo "Generated YAML file:"
cat "$yaml_file"
echo

# This script does tracing itself
../vn2/vn2-test-single-yaml-deploy.sh "$yaml_file"
if [ $? -ne 0 ]; then
  echo "Failed to deploy"
  exit 1
fi
$TRACE_SCRIPT --start 'vn2 logs'
if [ "$WAIT_FOR_OUTPUT" = "true" ]; then
  time=0
  while [ $time -lt 10 ]; do
    sleep 15 # waits for curl test to finish
    c-aci-testing vn2 logs | tee "$OUTPUT_DIR/output.log"
    if [ $? -ne 0 ]; then
      err_die "Failed to get logs"
    fi
    if grep -q 'OUTPUT: ' "$OUTPUT_DIR/output.log"; then
      break
    fi
    time=$((time + 1))
  done
else
  c-aci-testing vn2 logs | tee "$OUTPUT_DIR/output.log"
  if [ $? -ne 0 ]; then
    err_die "Failed to get logs"
  fi
fi
$TRACE_SCRIPT --complete --strict

if [ "$CLEANUP" != false ]; then
  c-aci-testing vn2 remove
fi
