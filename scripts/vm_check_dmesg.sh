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

found_sus_message=""
grep -i segfault $dmesg_file && found_sus_message+="segfault "
grep -i 'protection fault' $dmesg_file && found_sus_message+="protection-fault "
grep 'BUG:' $dmesg_file && found_sus_message+="kernel-bug "
grep 'WARNING:' $dmesg_file && found_sus_message+="kernel-bug "
grep 'RIP:' $dmesg_file && found_sus_message+="kernel-backtrace "
soft_lockup_count=$(grep 'watchdog: BUG: soft lockup' $dmesg_file | wc -l)
if [ "$soft_lockup_count" -gt 0 ]; then
  found_sus_message+="soft-lockup "
fi

cat $dmesg_file

if [ ! -s $dmesg_file ]; then
  echo "No dmesg output found"
  ./scripts/tracing/trace_step.py --complete --err "No dmesg output found" --strict
  exit 1
fi

./scripts/tracing/trace_step.py --complete --strict \
  --output "sus_messages=$found_sus_message" \
  --output "soft_lockup_count=$soft_lockup_count" \
  --err "$found_sus_message"

if [ -n "$found_sus_message" ]; then
  echo "Found suspicious message in dmesg: $found_sus_message"
  exit 1
fi
