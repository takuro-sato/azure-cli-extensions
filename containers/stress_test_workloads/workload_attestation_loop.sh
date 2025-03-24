#!/bin/bash

/server &

echo ------------- payload start attestation_loop --------------- | tee /dev/kmsg

while :; do
  ./attestation_loop
  status=$?
  if [ $status -ne 0 ]; then
    kill %1
    exit $status
  fi
done
