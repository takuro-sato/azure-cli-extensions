#!/bin/bash

if [ "$#" -lt 1 -o "$#" -gt 2 ]; then
    sname=$(basename "$0")
    echo "Usage: $sname <version to install>"
    echo "       $sname git <branch name>"
    exit 1
fi

set -euo pipefail

cd "$(dirname "$0")"

if [ "$1" != "git" ]; then
    version="$1"
    tgz_url="https://github.com/microsoft/confidential-aci-testing/releases/download/$version/c_aci_testing-$version.tar.gz"
    tgz_name="c-aci-testing.tar.gz"

    ./download_with_retry.sh "$tgz_url" "$tgz_name"
    pip install "$tgz_name"
    rm "$tgz_name"
else
    branch="$2"
    git clone 'https://github.com/microsoft/confidential-aci-testing.git' --branch "$branch" /tmp/c-aci-testing
    cd /tmp/c-aci-testing
    pip install flit
    flit install
fi
