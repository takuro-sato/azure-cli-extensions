#!/bin/sh

# This script need to be sh-compatible due to inlining it in vnet.bicep

echo Starting curl check from within container

ATTEMPTS=0
TIMEOUT=200
START_TS=$(date +%s)
SECS_SINCE_START=0
ERR_THRESHOLD_ATTEMPTS=2

while [ $SECS_SINCE_START -lt $TIMEOUT ]; do
  echo "resolv.conf:"
  cat /etc/resolv.conf
  echo
  ATTEMPTS=$((ATTEMPTS+1))
  SECS_SINCE_START=$(( $(date +%s) - $START_TS ))
  echo "Attempt $ATTEMPTS: $SECS_SINCE_START seconds since start"
  timeout -s INT 20s curl -sv https://management.azure.com > /dev/null
  if [ $? -eq 0 ]; then
    SECS_SINCE_START=$(( $(date +%s) - $START_TS ))
    echo "It worked"
    echo "OUTPUT: {\"curl_attempts\": $ATTEMPTS, \"curl_first_success_exit_time\": $SECS_SINCE_START}"
    if [ $ATTEMPTS -gt $ERR_THRESHOLD_ATTEMPTS ]; then
      echo "ERROR: Took more than $ERR_THRESHOLD_ATTEMPTS attempts to get a successful curl in the container"
      exit 1
    fi
    exit 0
  fi
  echo "Didn't work. Checking if DNS is working"
  timeout -s INT 20s host management.azure.com
  if [ $? -ne 0 ]; then
    echo "ERROR: DNS resolution failed"
  fi
  echo "Retrying in 5 seconds..."
  sleep 5
done
echo "ERROR: curl failed after $ATTEMPTS attempts, $TIMEOUT seconds"
