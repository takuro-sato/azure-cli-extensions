#!/usr/bin/bash
set -ex

echo Primary started

uname -a
dmesg | grep "Kernel command line"
dmesg | grep "Hyper-V: Host Build"
echo Reference info SHA256SUM: $(base64 -d < /security-context-*/reference-info-base64 | sha256sum)

sleep 5
# Attempt to curl server in sidecar
curl --fail-with-body 'http://127.0.0.1:8000'
sleep infinity
