#!/bin/bash

version="1.2.5"
tgz_url="https://github.com/microsoft/confidential-aci-testing/releases/download/$version/c_aci_testing-$version.tar.gz"
tgz_name="c-aci-testing.tar.gz"

attempts=0
while :; do
    echo "Downloading $tgz_url"
    curl -sL --fail -o "$tgz_name" "$tgz_url"
    if [ $? -eq 0 ]; then
        break
    else
        echo "Download failed."
        attempts=$((attempts + 1))
        if [ $attempts -ge 3 ]; then
            echo "Failed to download after 3 attempts."
            exit 1
        fi
        echo Retrying in 5s
        sleep 5
    fi
done

set -e

pip install "$tgz_name"
rm "$tgz_name"

# Workaround for a bug where bicep isn't in the expected location
if [ ! -f ~/.azure/bin/bicep ]; then
    mkdir -p ~/.azure/bin/
    curl -Lo ~/.azure/bin/bicep \
        https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64
    chmod +x ~/.azure/bin/bicep
fi

# Uncomment for private branch testing
# BRANCH=???
# git clone 'https://github.com/microsoft/confidential-aci-testing.git' --branch $BRANCH /tmp/c-aci-testing
# cd /tmp/c-aci-testing
# pip install flit
# flit install
