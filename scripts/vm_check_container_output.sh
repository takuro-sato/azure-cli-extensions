#!/usr/bin/env bash

set -e
./scripts/tracing/trace_step.py --start 'Check container output'
set +e
out_file="container_output.log"

c-aci-testing vm exec --deployment-name $DEPLOYMENT_NAME 'Get-Item C:\*\container_log_*.log | foreach { echo ""; echo ""; echo $_.FullName; cat -Raw $_ } > C:\container_output.log'
c-aci-testing vm cat --deployment-name $DEPLOYMENT_NAME 'C:\container_output.log' > $out_file
if [ $? -ne 0 ]; then
  echo "Failed to get container_output.log"
  cat $out_file
  ./scripts/tracing/trace_step.py --complete --err "Failed to get container_output.log" --strict
  exit 1
fi

cat $out_file

if [ ! -s $out_file ]; then
  echo "No output found"
  ./scripts/tracing/trace_step.py --complete --err "No output found" --strict
  exit 1
fi

error_count=$(grep 'ERROR' $out_file | wc -l)
err_str=""

if [ "$error_count" -gt 0 ]; then
  err_str="Found ERROR in container output"
fi

./scripts/tracing/trace_step.py --complete --strict \
  --output "error_count=$error_count" \
  --err "$err_str"
