#!/bin/bash

python3 server.py &

uname -a

echo ------------- payload start sysbench --------------- | tee /dev/kmsg

while :; do
  sysbench --threads=$(nproc) --time=60 --test=cpu --cpu-max-prime=15000 run
  status=$?
  if [ $status -ne 0 ]; then
    kill %1
    exit $status
  fi
done
kill %1
