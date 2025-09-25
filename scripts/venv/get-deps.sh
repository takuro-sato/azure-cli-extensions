#!/usr/bin/env bash

# This script is to populate the virtualenv with dependencies needed, then
# package it.  Things that are not included in the venv should be installed
# separately.

set -eo pipefail

VIRTUAL_ENV_DIR=${VIRTUAL_ENV_DIR:-/tmp/runner-venv}
C_ACI_TESTING_BRANCH=${C_ACI_TESTING_BRANCH:-}

if [ -n "$VIRTUAL_ENV" ]; then
    echo "This script must run outside any existing virtualenv"
    exit 1
fi

set -u

rm -rf "$VIRTUAL_ENV_DIR"
mkdir -p "$VIRTUAL_ENV_DIR"

echo "Creating virtualenv in $VIRTUAL_ENV_DIR"
python3 -m venv "$VIRTUAL_ENV_DIR"

export VIRTUAL_ENV="$VIRTUAL_ENV_DIR"
echo "VIRTUAL_ENV=$VIRTUAL_ENV"
export PATH="$VIRTUAL_ENV/bin:$PATH"

echo "Upgrade pip"
pip install --upgrade pip

echo Install required azure-sdk
pip install azure-kusto-data azure-storage-blob

if [ -n "$C_ACI_TESTING_BRANCH" ]; then
    echo Install c_aci_testing from branch $C_ACI_TESTING_BRANCH
    ./scripts/install-c-aci-testing.sh git "$C_ACI_TESTING_BRANCH"
else
    echo Install c_aci_testing $C_ACI_TESTING_VERSION
    ./scripts/install-c-aci-testing.sh "$C_ACI_TESTING_VERSION"
fi

# We put required binaries in the venv package as well to avoid flaky
# re-download in every run
./scripts/download_with_retry.sh \
    "https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64" \
    "$VIRTUAL_ENV_DIR/bin/bicep"
chmod +x "$VIRTUAL_ENV_DIR/bin/bicep"

ORAS_VERSION="1.2.2"
rm -rf /tmp/oras-install
./scripts/download_with_retry.sh \
    "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz" \
    "/tmp/oras_${ORAS_VERSION}_linux_amd64.tar.gz"
mkdir /tmp/oras-install
tar -xzf "/tmp/oras_${ORAS_VERSION}_linux_amd64.tar.gz" -C "/tmp/oras-install" oras
mv "/tmp/oras-install/oras" "$VIRTUAL_ENV_DIR/bin/oras"
rm "/tmp/oras_${ORAS_VERSION}_linux_amd64.tar.gz"
chmod +x "$VIRTUAL_ENV_DIR/bin/oras"

SIGN1UTIL_VERSION="1.4.0"
./scripts/download_with_retry.sh \
    "https://github.com/microsoft/cosesign1go/releases/download/v${SIGN1UTIL_VERSION}/sign1util" \
    "$VIRTUAL_ENV_DIR/bin/sign1util"
chmod +x "$VIRTUAL_ENV_DIR/bin/sign1util"

set +u

if [ -n "$GITHUB_ENV" ]; then
    echo "VIRTUAL_ENV=$VIRTUAL_ENV" >> $GITHUB_ENV
    echo "PATH=$PATH" >> $GITHUB_ENV
else
    echo "Not running in GitHub Actions, skip setting GITHUB_ENV"
fi
