#!/usr/bin/env bash

set +e

if [ -z "$DEPLOYMENT_NAME" ]; then
  echo "DEPLOYMENT_NAME is not set"
  exit 1
fi

script_dir="$(dirname "$0")"

$script_dir/tracing/trace_step.py --start "vm create $DEPLOYMENT_NAME"
err_file=`mktemp`
c-aci-testing vm create 2> "$err_file"
status=$?
cat "$err_file" >&2
output_flags=(
  "--output"
  "VM_SIZE=$VM_SIZE"
  "VM_IMAGE=$VM_IMAGE"
  "USE_OFFICIAL_IMAGES=$USE_OFFICIAL_IMAGES"
  "CPLAT_BLOB_NAME=$CPLAT_BLOB_NAME"
  "WIN_FLAVOR=$WIN_FLAVOR"
  "VM_ZONE=$VM_ZONE"
)
if [ $status -ne 0 ]; then
  $script_dir/tracing/trace_step.py --complete "${output_flags[@]}" --err "$(printf "Failed to deploy VM %s:\n%s" "$DEPLOYMENT_NAME" "$(cat "$err_file")")" --strict
else
  $script_dir/tracing/trace_step.py --complete "${output_flags[@]}" --strict
fi
exit $status
