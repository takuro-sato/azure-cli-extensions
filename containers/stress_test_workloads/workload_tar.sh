#!/bin/bash

/server &

echo ------------- payload start taring --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

cd /
while :; do
  nice -n +10 tar -c {bin,etc,home,lib,opt,root,sbin,usr,var} > /dev/null
  status=$?
  if [ $status -ne 0 ]; then
    kill %1
    exit $status
  fi
done
