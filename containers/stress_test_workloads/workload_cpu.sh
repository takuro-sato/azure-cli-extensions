#!/bin/bash

/server &
SERVER_PID=$!

{
  echo ------------- payload start check_threads --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

  while :; do
    ./check_threads
    status=$?
    if [ $status -ne 0 ]; then
      kill $SERVER_PID
      exit $status
    fi
  done
} &

echo ------------- payload start sysbench --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

while :; do
  nice -n +10 sysbench --threads=$(nproc) --time=60 cpu --cpu-max-prime=15000 run
  status=$?
  if [ $status -ne 0 ]; then
    kill %1
    exit $status
  fi
done
kill %1
