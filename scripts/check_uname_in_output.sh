#!/usr/bin/env bash

output_file="$1"
if [ -z "$output_file" ]; then
  echo "Usage: $0 <output_file>"
  exit 1
fi
if [ ! -f "$output_file" ]; then
  echo "Output file $output_file not found"
  exit 1
fi
kernel_date=`grep -oP '(?<=PREEMPT_DYNAMIC ).+(?= x86_64)' $output_file`
if [ -z "$kernel_date" ]; then
  echo "Failed to find uname line in $output_file"
  exit 1
fi
echo "Kernel build date: $kernel_date"
kernel_build_ts=`date -d "$kernel_date" +%s` || { echo "Failed to parse kernel build date"; exit 1; }
expected_kernel_date="$ACI_EXPECTED_KERNEL_DATE"
echo "Expected kernel build date: $expected_kernel_date"
expected_kernel_build_ts=`date -d "$expected_kernel_date" +%s` || { echo "Failed to parse expected kernel build date"; exit 1; }
if [ $kernel_build_ts -lt $expected_kernel_build_ts ]; then
  echo "Kernel build date is older than expected"
  echo "Uname:" `grep 'x86_64 Linux' $output_file`
  exit 1
fi
