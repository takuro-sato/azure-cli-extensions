#!/bin/bash
# workload_fio.sh and workload_cpu.sh together, with changes

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

{
  echo ------------- payload start fio --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

  while :; do
    nice -n +10 fio  --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=64k --iodepth=64 --readwrite=randrw --size=500M --loop=1000 --max-jobs=$(nproc)
    status=$?
    if [ $status -ne 0 ]; then
      kill $SERVER_PID
      exit $status
    fi
  done
} &

echo ------------- payload start sysbench --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"
while :; do
  nice -n +10 sysbench --threads=$(nproc) --time=10000 cpu run
  status=$?
  if [ $status -ne 0 ]; then
    kill $SERVER_PID
    exit $status
  fi
done
kill $SERVER_PID
