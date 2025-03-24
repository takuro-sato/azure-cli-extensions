#!/usr/bin/env bash

set -e
./scripts/tracing/trace_step.py --start 'Check dmesg'
set +e
dmesg_file="dmesg.log"

c-aci-testing vm exec --deployment-name $DEPLOYMENT_NAME 'Get-Item C:\*\dmesg*.log | foreach { echo ""; echo ""; echo $_.FullName; cat -Raw $_ } > C:\all-dmesg.log'
c-aci-testing vm cat --deployment-name $DEPLOYMENT_NAME 'C:\all-dmesg.log' > $dmesg_file
if [ $? -ne 0 ]; then
  echo "Failed to get dmesg."
  cat $dmesg_file
  ./scripts/tracing/trace_step.py --complete --err "Failed to get dmesg" --strict
  exit 1
fi

# will call trace --complete
./scripts/_check_dmesg.sh "$dmesg_file"
