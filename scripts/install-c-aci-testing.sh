#!/bin/bash

version="1.0.14"
curl -sL "$(\
    curl -s "https://api.github.com/repos/microsoft/confidential-aci-testing/releases/tags/$version" \
        | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url')" \
            -o c-aci-testing.tar.gz
pip install c-aci-testing.tar.gz
rm c-aci-testing.tar.gz
