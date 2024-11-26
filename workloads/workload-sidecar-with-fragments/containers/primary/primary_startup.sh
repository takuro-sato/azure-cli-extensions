#!/usr/bin/bash
set -ex

echo Primary started
sleep 5
# Attempt to curl server in sidecar
curl --fail-with-body 'http://127.0.0.1:8000'
sleep infinity
