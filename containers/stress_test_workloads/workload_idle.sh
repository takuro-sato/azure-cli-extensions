#!/bin/bash
# A "baseline" case running only the Python server

/server &
SERVER_PID=$!

echo ------------- payload does nothing --------------- | tee /dev/kmsg

sleep infinity
