#!/usr/bin/env bash

set -euo pipefail

environment_file="${1:-cacitesting.env}"
shift || true
preserved_variables=("$@")

if [[ ! "$environment_file" =~ ^cacitesting([.][A-Za-z0-9_-]+)?[.]env$ ]]; then
    echo "Environment must be a root-level cacitesting*.env file: $environment_file" >&2
    exit 1
fi

if [[ ! -f "$environment_file" ]]; then
    echo "Environment file does not exist: $environment_file" >&2
    exit 1
fi

: "${GITHUB_ENV:?GITHUB_ENV must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

set +u
set -a
source "$environment_file"
set +a
set -u

: "${SUBSCRIPTION:?SUBSCRIPTION must be set in $environment_file}"
: "${RESOURCE_GROUP:?RESOURCE_GROUP must be set in $environment_file}"
: "${REGISTRY:?REGISTRY must be set in $environment_file}"

while IFS= read -r variable_name; do
    case "$variable_name" in
        LOCATION|MANAGED_IDENTITY|DEPLOYMENT_NAME|POLICY_TYPE|REPOSITORY|TAG)
            continue
            ;;
    esac

    for preserved_variable in "${preserved_variables[@]}"; do
        if [[ "$variable_name" == "$preserved_variable" ]]; then
            continue 2
        fi
    done

    variable_value="${!variable_name-}"
    if [[ "$variable_value" == *$'\n'* || "$variable_value" == *$'\r'* ]]; then
        echo "Multiline environment values are not supported: $variable_name" >&2
        exit 1
    fi
    printf '%s=%s\n' "$variable_name" "$variable_value" >> "$GITHUB_ENV"
done < <(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$environment_file" | sort -u)

printf 'subscription=%s\n' "$SUBSCRIPTION" >> "$GITHUB_OUTPUT"
