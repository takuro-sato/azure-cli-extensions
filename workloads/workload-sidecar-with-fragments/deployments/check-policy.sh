#!/usr/bin/env bash

REGO_FILE="$1"

if [ -z "$REGO_FILE" ] || [ "$#" -ne 1 ]; then
  echo "Usage: $0 <rego_file>"
  exit 1
fi

if grep --color=always -C5 'sidecar_server.py' "$REGO_FILE"; then
  echo "Error: sidecar container detected in primary policy"
  exit 1
fi
