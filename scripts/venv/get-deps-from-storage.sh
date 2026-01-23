#!/usr/bin/env bash

STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-cacitestingstorageaci}
STORAGE_CONTAINER=${STORAGE_CONTAINER:-blobs}
VIRTUAL_ENV_DIR=${VIRTUAL_ENV_DIR:-/tmp/runner-venv}

set -euo pipefail
STORAGE_NAME="runner-venv-c-aci-testing-${C_ACI_TESTING_VERSION}.tar.gz"

echo "Downloading venv package from $STORAGE_ACCOUNT/$STORAGE_CONTAINER/$STORAGE_NAME"

attempt=0
next_sleep_secs=5
while :; do
    if az storage blob download \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$STORAGE_CONTAINER" \
        --name "$STORAGE_NAME" \
        --auth-mode login \
        --file /tmp/runner-venv.tar.gz \
        --only-show-errors; then
        break
    else
        echo "az storage blob download failed."
        attempt=$((attempt + 1))
        if [ $attempt -ge 3 ]; then
            echo "Failed to download venv package after 3 attempts."
            exit 1
        fi
        echo Retrying in ${next_sleep_secs}s
        sleep $next_sleep_secs
        next_sleep_secs=$((next_sleep_secs * next_sleep_secs))
    fi
done

echo "Extracting venv package"
mkdir -p "$VIRTUAL_ENV_DIR"
tar -xzf /tmp/runner-venv.tar.gz -C "$VIRTUAL_ENV_DIR"
rm /tmp/runner-venv.tar.gz

export VIRTUAL_ENV="$VIRTUAL_ENV_DIR"
echo "VIRTUAL_ENV=$VIRTUAL_ENV" >> $GITHUB_ENV
echo "PATH=$VIRTUAL_ENV/bin:$PATH" >> $GITHUB_ENV
