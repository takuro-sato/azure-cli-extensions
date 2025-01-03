#!/usr/bin/bash

VERSION="$1"

attempts=0
while :; do
    az extension add -n confcom --version "$VERSION" --upgrade
    if [ $? -eq 0 ]; then
        break
    else
        echo "az extension add failed."
        attempts=$((attempts + 1))
        if [ $attempts -ge 3 ]; then
            echo "Failed to install confcom after 3 attempts."
            exit 1
        fi
        echo Retrying in 5s
        sleep 5
    fi
done

exit 0
