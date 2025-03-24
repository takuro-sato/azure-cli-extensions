#!/usr/bin/bash

dmesg_file="$1"
if [ -z "$dmesg_file" ] || [ $# -ne 1 ]; then
  echo "Usage: $0 <dmesg_file>"
  exit 1
fi

trace_script="$(realpath "$(dirname "$0")/tracing/trace_step.py")"

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
  $trace_script --complete --err "No dmesg output found" --strict
  exit 1
fi

$trace_script --complete --strict \
  --output "sus_messages=$found_sus_message" "soft_lockup_count=$soft_lockup_count" \
  --err "$found_sus_message"

if [ -n "$found_sus_message" ]; then
  echo "Found suspicious message in dmesg: $found_sus_message"
  exit 1
fi
