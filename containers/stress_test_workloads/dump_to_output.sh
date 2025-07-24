#!/bin/bash

echo "Started at: $(date)"
echo "uptime:
$(uptime)"

uname -a
dmesg | grep "Kernel command line"
dmesg | grep "Hyper-V: Host Build"
echo Reference info SHA256SUM: $(base64 -d < /security-context-*/reference-info-base64 | sha256sum)

sleep 80
echo "-------- Stress test container alive --------"
echo "dmesg:"
dmesg
