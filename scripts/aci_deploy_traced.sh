#!/usr/bin/env bash

set +e

if [ -z "$DEPLOYMENT_NAME" ]; then
  echo "DEPLOYMENT_NAME is not set"
  exit 1
fi

MAX_DURATION_MS=1200000

script_dir="$(dirname "$0")"

args=("$@")
$script_dir/tracing/trace_step.py --start "aci deploy $DEPLOYMENT_NAME"
out_file=`mktemp`
err_file=`mktemp`
c-aci-testing aci deploy "${args[@]}" --timeout 3600 --deploy-output-file "$out_file" 2> "$err_file"
status=$?
cat "$out_file"
out_file_is_valid=$(jq -r '.' < "$out_file" > /dev/null 2>&1 && echo "true" || echo "false")
cat "$err_file" >&2
if [ $status -ne 0 ]; then
  err_str=""
  if [[ "$out_file_is_valid" == "true" ]]; then
    err_str="$(jq -r '.error' < "$out_file") (correlation ID: $(jq -r '.correlationId' < "$out_file"))"
  else
    err_str="$(cat "$err_file")"
  fi
  $script_dir/tracing/trace_step.py --complete --err "$(printf "Failed to deploy to %s:\n%s" "$DEPLOYMENT_NAME" "$err_str")" --strict --output-from-stdin < "$out_file"
else
  durationMs=$(jq -r '.durationMs' < "$out_file")
  if [ "$durationMs" -le "$MAX_DURATION_MS" ]; then
    $script_dir/tracing/trace_step.py --complete --strict --output-from-stdin < "$out_file"
  else
    $script_dir/tracing/trace_step.py --complete --err "Deployment succeed, but exceeded $((MAX_DURATION_MS / 1000 / 60)) minutes (took $((durationMs / 1000 / 60)) minutes)" --strict --output-from-stdin < "$out_file"
  fi
fi
rm "$out_file" "$err_file"
exit $status
