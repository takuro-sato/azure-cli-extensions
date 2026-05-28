#!/bin/bash

/server &

echo ------------- payload start attestation_loop --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

while :; do
  ./attestation_loop
  status=$?
  if [ $status -ne 0 ]; then
    kill %1
    exit $status
  fi
done
