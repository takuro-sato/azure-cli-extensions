#!/bin/bash

version="1.2.11"
tgz_url="https://github.com/microsoft/confidential-aci-testing/releases/download/$version/c_aci_testing-$version.tar.gz"
tgz_name="c-aci-testing.tar.gz"

set -e
cd "$(dirname "$0")"

./download_with_retry.sh "$tgz_url" "$tgz_name"

pip install "$tgz_name"
rm "$tgz_name"

# Workaround for a bug where bicep isn't in the expected location
if [ ! -f ~/.azure/bin/bicep ]; then
    mkdir -p ~/.azure/bin/
    ./download_with_retry.sh \
        "https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64" \
        ~/.azure/bin/bicep
    chmod +x ~/.azure/bin/bicep
fi

# Uncomment for private branch testing
# BRANCH=???
# git clone 'https://github.com/microsoft/confidential-aci-testing.git' --branch $BRANCH /tmp/c-aci-testing
# cd /tmp/c-aci-testing
# pip install flit
# flit install
