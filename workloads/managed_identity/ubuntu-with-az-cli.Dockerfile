FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
RUN apt-get update && apt-get install -y \
    bash curl ca-certificates python3-pip && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --break-system-packages azure-cli
