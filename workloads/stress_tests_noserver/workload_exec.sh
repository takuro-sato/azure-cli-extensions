#!/bin/bash

./dump_to_output.sh &

echo ------------- payload start ls loop --------------- | tee /dev/kmsg

while :; do
  ls loooooooooooooooooooooooooooooooooooooooonnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnggggggggggggggggggggg 2>/dev/null
  status=$?
  if [ $status -eq 139 ]; then # SEGV
    kill %1
    exit $status
  fi
done
