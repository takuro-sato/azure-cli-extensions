#!/usr/bin/env bash

TRACE_SCRIPT="$(realpath "$(dirname "$0")/tracing/trace_step.py")"

output_file="$1"
if [ -z "$output_file" ]; then
  echo "Usage: $0 <output_file>"
  exit 1
fi

$TRACE_SCRIPT --start 'Check correct kernel version'

function fail() {
  echo "$1"
  $TRACE_SCRIPT --complete --strict --err "$1"
  exit 1
}

if [ ! -f "$output_file" ]; then
  fail "Output file $output_file not found"
fi
kernel_date=`grep -oP '(?<=PREEMPT_DYNAMIC ).+(?= x86_64)' $output_file | head -n 1`
if [ -z "$kernel_date" ]; then
  fail "Failed to find uname line in $output_file"
fi
ver_check_log="$(mktemp)"
echo "Kernel build date: $kernel_date" | tee -a $ver_check_log
kernel_build_ts=`date -d "$kernel_date" +%s` || fail "Failed to parse kernel build date"
expected_kernel_date="$ACI_EXPECTED_KERNEL_DATE"
echo "Expected kernel build date: $expected_kernel_date" | tee -a $ver_check_log
expected_kernel_build_ts=`date -d "$expected_kernel_date" +%s` || fail "Failed to parse expected kernel build date"
if [ $kernel_build_ts -lt $expected_kernel_build_ts ]; then
  fail "Kernel build date is older than expected
Uname: $(grep 'x86_64 Linux' $output_file)"
fi
rm -f $ver_check_log
