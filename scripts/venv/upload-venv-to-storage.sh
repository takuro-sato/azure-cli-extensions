#!/usr/bin/env bash

STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-cacitestingstorage}
STORAGE_CONTAINER=${STORAGE_CONTAINER:-blobs}
VIRTUAL_ENV_DIR=${VIRTUAL_ENV_DIR:-/tmp/runner-venv}

if [ ! -d "$VIRTUAL_ENV_DIR" ]; then
    echo "$VIRTUAL_ENV_DIR does not exist"
    exit 1
fi

set -euo pipefail

STORAGE_NAME="runner-venv-c-aci-testing-${C_ACI_TESTING_VERSION}.tar.gz"

echo "Uploading current venv to $STORAGE_ACCOUNT/$STORAGE_CONTAINER/$STORAGE_NAME"
tar -czf /tmp/runner-venv.tar.gz -C "$VIRTUAL_ENV_DIR" .
attempt=0
next_sleep_secs=5
while :; do
    if az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$STORAGE_CONTAINER" \
        --name "$STORAGE_NAME" \
        --auth-mode login \
        --file /tmp/runner-venv.tar.gz \
        --overwrite \
        --only-show-errors; then
        break
    else
        echo "az storage blob upload failed."
        attempt=$((attempt + 1))
        if [ $attempt -ge 3 ]; then
            echo "Failed to upload venv package after 3 attempts."
            exit 1
        fi
        echo Retrying in ${next_sleep_secs}s
        sleep $next_sleep_secs
        next_sleep_secs=$((next_sleep_secs * next_sleep_secs))
    fi
done

rm /tmp/runner-venv.tar.gz
