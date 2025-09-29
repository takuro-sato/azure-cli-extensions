#!/usr/bin/bash

set -e

echo Set Azure CLI flag to avoid polluting telemetry metrics
az config set core.collect_telemetry=false --only-show-errors

export CONFCOM_VERSION="1.2.8"
export C_ACI_TESTING_VERSION="1.2.13"
export C_ACI_TESTING_BRANCH=""

if [ -n "$INIT_RUN_POPULATE_CACHE" ]; then
  if ! ./scripts/venv/get-deps.sh; then
    echo "Failed to build venv"
    exit 1
  fi

  # Apply environment variables that will make us use the new venv
  . "$GITHUB_ENV"

  ./scripts/venv/upload-venv-to-storage.sh
  exit $?
fi

if [ -z "$C_ACI_TESTING_BRANCH" ]; then
  echo Get pre-cached virtualenv
  if ! ./scripts/venv/get-deps-from-storage.sh; then
    echo "Failed to get pre-cached venv, building from scratch, failing back to fresh download"
    if ! ./scripts/venv/get-deps.sh; then
      echo "Failed to build venv"
      exit 1
    fi
  fi
else
  echo Build virtualenv from scratch as C_ACI_TESTING_BRANCH is set
  if ! ./scripts/venv/get-deps.sh; then
    echo "Failed to build venv"
    exit 1
  fi
fi

# Apply environment variables that will make us use the new venv
. "$GITHUB_ENV"

# Workaround for a bug where bicep isn't in the expected location
if [ ! -f ~/.azure/bin/bicep ]; then
  echo "Placing bicep binary into ~/.azure/bin"
  mkdir -p ~/.azure/bin/
  cp "$VIRTUAL_ENV/bin/bicep" ~/.azure/bin/bicep
  chmod +x ~/.azure/bin/bicep
fi

echo Install confcom $CONFCOM_VERSION
./scripts/install-confcom.sh "$CONFCOM_VERSION"

echo Start run trace
./scripts/tracing/new_run.py

if [ -e /opt/az-config/config ]; then
  echo "Fixup bad permission in github runner image:"
  sudo ls -la /opt/az-config
  sudo chown -Rv $(id -un):$(id -gn) /opt/az-config
fi

echo Setup Docker
sudo usermod -aG docker $USER
