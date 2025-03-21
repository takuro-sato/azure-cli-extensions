#!/bin/sh

# This script need to be sh-compatible due to inlining it in vnet.bicep

echo Starting curl check from within container

ATTEMPTS=0
TIMEOUT=200
START_TS=$(date +%s)
SECS_SINCE_START=0
ERR_THRESHOLD_ATTEMPTS=1

while [ $SECS_SINCE_START -lt $TIMEOUT ]; do
  echo "resolv.conf:"
  cat /etc/resolv.conf
  echo
  ATTEMPTS=$((ATTEMPTS+1))
  SECS_SINCE_START=$(( $(date +%s) - $START_TS ))
  echo "Attempt $ATTEMPTS: $SECS_SINCE_START seconds since start"
  timeout -s INT 20s curl -sv http://example.com > /dev/null
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
  echo "Didn't work, trying without dependency on DNS"
  timeout -s INT 20s curl -sv http://1.1.1.1
  if [ $? -eq 0 ]; then
    echo "Hmm... that worked. DNS broken?"
    echo "Retrying..."
    continue
  fi
  echo "That still didn't work - outbound networking is broken."
  echo "Retrying in 5 seconds..."
  sleep 5
done
echo "ERROR: curl failed after $ATTEMPTS attempts, $TIMEOUT seconds"
