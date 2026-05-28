#!/bin/bash
# A "baseline" case running only the Python server

/server &
SERVER_PID=$!

echo ------------- payload does nothing --------------- | tee "$([ -c /dev/kmsg ] && echo /dev/kmsg || echo /dev/null)"

sleep infinity
