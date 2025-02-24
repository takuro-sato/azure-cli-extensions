#!/usr/bin/env bash

set -e
./scripts/tracing/trace_step.py --start "Check container output until all containers terminate."
set +e
out_file="container_output.log"

consecutive_failures=0
bytes_streamed=0
while :; do
  if [ $consecutive_failures -ge 2 ]; then
    echo "Failed to get container output for 2 consecutive times"
    ./scripts/tracing/trace_step.py --complete --err "Failed to get container output for 2 consecutive times" --strict
    exit 1
  fi
  sleep 30
  c-aci-testing vm exec --deployment-name $DEPLOYMENT_NAME '
    Get-Item C:\*\container_log_*.log | foreach { echo ""; echo ""; echo $_.FullName; cat -Raw $_ } > C:\container_output.log;
    if ((C:\ContainerPlat\crictl.exe ps -o json | ConvertFrom-Json).containers.Length -eq 0) {
      echo 'ALL-CONTAINERS-TERMINATED' >> C:\container_output.log
    }
  ' > /dev/null
  if [ $? -ne 0 ]; then
    echo "Failed to execute command to get container log"
    consecutive_failures=$((consecutive_failures + 1))
    continue
  fi
  c-aci-testing vm cat --deployment-name $DEPLOYMENT_NAME 'C:\container_output.log' > "$out_file"
  if [ $? -ne 0 ]; then
    echo "Failed to get container_output.log"
    cat "$out_file"
    consecutive_failures=$((consecutive_failures + 1))
    continue
  fi
  consecutive_failures=0
  new_nb_bytes=$(wc -c < "$out_file")
  if [ "$new_nb_bytes" -gt "$bytes_streamed" ]; then
    tail --bytes=+${bytes_streamed} "$out_file"
    bytes_streamed=$new_nb_bytes
  fi
  if grep -q 'ALL-CONTAINERS-TERMINATED' "$out_file"; then
    echo "No more containers running"
    break
  fi
done

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
