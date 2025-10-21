#!/usr/bin/bash

script_to_run="$1"
if [ -z "$script_to_run" ]; then
    script_to_run="./info_check.sh"
fi

$script_to_run
status=$?
if [ $status -ne 0 ]; then
    echo "$script_to_run failed with status $status"
fi

# Keep container alive to avoid restart loop for vn2
sleep infinity
