#!/bin/bash

python3 server.py &
SERVER_PID=$!

uname -a

echo ------------- payload start multicpu --------------- | tee /dev/kmsg

{
  echo ------------- payload start fio --------------- | tee /dev/kmsg

  while :; do
    fio  --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=64k --iodepth=64 --readwrite=randrw --size=500M --loop=1000 --max-jobs=$(nproc)
    status=$?
    if [ $status -ne 0 ]; then
      kill $SERVER_PID
      exit $status
    fi
  done
} &

while :; do
  ./multicpu --num-threads $(nproc) | tee log >/dev/kmsg 2>/dev/kmsg
  status=$?
  if [ $status -ne 0 ]; then
    kill $SERVER_PID
    exit $status
  fi
done
kill $SERVER_PID
