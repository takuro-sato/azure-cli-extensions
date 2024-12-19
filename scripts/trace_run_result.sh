#!/usr/bin/bash

gh_status="$1"

case $gh_status in
  success)
    ./scripts/tracing/trace_step.py --complete
    ;;
  failure)
    ./scripts/tracing/trace_step.py --complete --err 'Failed'
    ;;
  cancelled)
    ./scripts/tracing/trace_step.py --complete --err 'Cancelled'
    ;;
esac
