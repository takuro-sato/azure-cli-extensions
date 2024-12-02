#!/bin/bash

version="1.0.17"
curl -sL "$(\
    curl -s "https://api.github.com/repos/microsoft/confidential-aci-testing/releases/tags/$version" \
        | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url')" \
            -o c-aci-testing.tar.gz
pip install c-aci-testing.tar.gz
rm c-aci-testing.tar.gz

# Uncomment for private branch testing
# BRANCH=???
# git clone 'https://github.com/microsoft/confidential-aci-testing.git' --branch $BRANCH /tmp/c-aci-testing
# cd /tmp/c-aci-testing
# pip install flit
# flit install
