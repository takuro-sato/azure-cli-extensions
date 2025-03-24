#!/bin/bash

/server &

echo ------------- payload start check_threads --------------- | tee /dev/kmsg

while :; do
  ./check_threads
  status=$?
  if [ $status -ne 0 ]; then
    kill $SERVER_PID
    exit $status
  fi
done
