#!/bin/bash
# A "baseline" case running only the Python server

./dump_to_output.sh &
SERVER_PID=$!

uname -a

echo ------------- payload does nothing --------------- | tee /dev/kmsg

sleep infinity
