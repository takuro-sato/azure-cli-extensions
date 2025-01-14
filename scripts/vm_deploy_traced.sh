#!/usr/bin/env bash

set +e

if [ -z "$DEPLOYMENT_NAME" ]; then
  echo "DEPLOYMENT_NAME is not set"
  exit 1
fi

script_dir="$(dirname "$0")"

args=("$@")
$script_dir/tracing/trace_step.py --start "vm deploy $DEPLOYMENT_NAME"
err_file=`mktemp`
c-aci-testing vm deploy "${args[@]}" 2> "$err_file"
status=$?
cat "$err_file" >&2
if [ $status -ne 0 ]; then
  $script_dir/tracing/trace_step.py --complete --err "$(printf "Failed to deploy to %s:\n%s" "$DEPLOYMENT_NAME" "$(cat "$err_file")")" --strict
else
  $script_dir/tracing/trace_step.py --complete --strict
fi
exit $status
