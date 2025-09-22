#!/bin/bash

url=$1
output=$2
max_retries=3
attempt=0
next_sleep_time=5

echo "Downloading $url to $output"

while [ $attempt -lt $max_retries ]; do
    if curl -vL --fail -o "$output" "$url"; then
        exit 0
    fi
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_retries ]; then
        break
    fi
    echo "Download failed. Retrying in $next_sleep_time seconds..."
    sleep $next_sleep_time
    next_sleep_time=$((next_sleep_time * next_sleep_time))
done

echo "Failed to download $url after $max_retries attempts."
exit 1
