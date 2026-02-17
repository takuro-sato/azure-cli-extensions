#!/usr/bin/bash
set -ex

echo Primary started

uname -a
dmesg | grep "Kernel command line"
dmesg | grep "Hyper-V: Host Build"
echo Reference info SHA256SUM: $(base64 -d < /security-context-*/reference-info-base64 | sha256sum)

sleep 5
# Attempt to curl server in sidecar
for i in $(seq 1 10); do
    if curl --fail-with-body 'http://127.0.0.1:8000'; then
        echo "curl sidecar succeeded"
        break
    fi
    if [ $i -lt 9 ]; then
        echo "Attempt $i failed, retrying in 5 seconds..."
        sleep 5
    else
        echo "All 3 attempts failed"
        echo "ERROR: failed to curl sidecar"
        sleep infinity
    fi
done
sleep infinity
