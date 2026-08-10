#!/usr/bin/env bash

set -euo pipefail

: "${LOCATION:?LOCATION must be set}"
: "${GITHUB_ENV:?GITHUB_ENV must be set}"

attestation_endpoint=$(awk -F, -v location="$LOCATION" '
    NR > 1 && $1 == "PROD" && $2 == location { print $3; exit }
' azure/MAA-endpoints.csv)

if [[ -z "$attestation_endpoint" ]]; then
    echo "No regional MAA endpoint found for location $LOCATION" >&2
    exit 1
fi

echo "Using regional MAA endpoint for $LOCATION: $attestation_endpoint"
printf 'ATTESTATION_ENDPOINT=%s\n' "$attestation_endpoint" >> "$GITHUB_ENV"
