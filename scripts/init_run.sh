#!/usr/bin/bash

set -e

echo Install azure-kusto-data
pip install azure-kusto-data

echo Start run trace
./scripts/tracing/new_run.py

echo Install c_aci_testing package
./scripts/install-c-aci-testing.sh

echo Set Confcom Version
./scripts/install-confcom.sh 1.2.0

echo Setup Docker
sudo usermod -aG docker $USER
