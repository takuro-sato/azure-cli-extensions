#!/usr/bin/env bash

if [[ $# -ne 1 && $# -ne 2 ]]; then
  echo "Usage: $0 <url> [output_file]"
  exit 1
fi
url="$1"
out_file="$2"
if [[ -z "$out_file" ]]; then
  out_file=$(mktemp)
fi

set -e

TRACE_SCRIPT="$(realpath "$(dirname "$0")/tracing/trace_step.py")"

$TRACE_SCRIPT --start 'Curl check with retry'

attempts=0
start_time=$(date +%s)
seconds_since_start=0
timeout=200
while [ $seconds_since_start -lt $timeout ]; do
  echo "[${seconds_since_start}s] Attempt $((attempts + 1))"

  # We want to limit the total amount of time this curl command can run for,
  # rather than just connect time, so that if the server accepts the request
  # but then hangs we also exit. This necessitates the use of `timeout`.
  set +e
  timeout -s INT 20 curl -v --fail-with-body -s "$url" -o "$out_file"
  status=$?
  set -e
  seconds_since_start=$(( $(date +%s) - $start_time ))
  if [ $status -eq 0 ]; then
    cat "$out_file"
    break
  fi
  attempts=$((attempts + 1))
  echo "Attempt $attempts failed"
  if [ $((timeout - seconds_since_start)) -gt 5 ]; then
    echo "Retrying in 5 seconds..."
    sleep 5
  else
    echo "curl failed $attempts times after $seconds_since_start seconds"
    $TRACE_SCRIPT \
      --complete \
      --output "failedAttempts=$attempts" \
               "secondsSinceStart=$seconds_since_start" \
      --err "curl failed $attempts times after $timeout seconds" \
      --strict
    exit 1
  fi
done
$TRACE_SCRIPT \
  --complete \
  --output "failedAttempts=$attempts" \
           "secondsSinceStart=$seconds_since_start" \
  --strict
exit 0
