#!/usr/bin/bash

set -e

echo Install required azure-sdk
pip install azure-kusto-data azure-storage-blob

echo Start run trace
./scripts/tracing/new_run.py

echo Install c_aci_testing package
./scripts/install-c-aci-testing.sh

echo Set Confcom Version
./scripts/install-confcom.sh 1.2.4

if [ -e /opt/az-config/config ]; then
  echo "Fixup bad permission in github runner image:"
  sudo ls -la /opt/az-config
  sudo chown -Rv $(id -un):$(id -gn) /opt/az-config
fi

echo Setup Docker
sudo usermod -aG docker $USER
