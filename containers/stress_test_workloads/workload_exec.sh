#!/bin/bash

/server &

echo ------------- payload start ls loop --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

while :; do
  ls loooooooooooooooooooooooooooooooooooooooonnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnggggggggggggggggggggg 2>/dev/null
  status=$?
  if [ $status -eq 139 ]; then # SEGV
    kill %1
    exit $status
  fi
done
