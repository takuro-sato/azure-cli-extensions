#!/bin/bash

cat <<EOF
Started at: $(date)

uptime:
$(uptime)

uname:
$(uname -a)
EOF

sleep 80
echo "-------- Stress test container alive --------"
echo "dmesg:"
dmesg
