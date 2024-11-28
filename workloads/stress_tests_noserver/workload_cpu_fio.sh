#!/bin/bash
# workload_fio.sh and workload_cpu.sh together, with changes

./dump_to_output.sh &
SERVER_PID=$!

uname -a

echo ------------- payload start sysbench --------------- | tee /dev/kmsg

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
  sysbench --threads=$(nproc) --time=10000 cpu run
  status=$?
  if [ $status -ne 0 ]; then
    kill $SERVER_PID
    exit $status
  fi
done
kill $SERVER_PID
