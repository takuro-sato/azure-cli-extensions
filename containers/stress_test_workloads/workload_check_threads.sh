#!/bin/bash

/server &
SERVER_PID=$!

echo ------------- payload start check_threads --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

while :; do
  ./check_threads
  status=$?
  if [ $status -ne 0 ]; then
    kill $SERVER_PID
    exit $status
  fi
done
