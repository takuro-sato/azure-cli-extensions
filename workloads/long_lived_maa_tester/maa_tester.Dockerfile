FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends python3 python3-requests python3-azure-kusto-data \
        curl tcpdump net-tools bind9-host ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY main.py /main.py
COPY MAA-endpoints.csv /MAA-endpoints.csv
LABEL org.opencontainers.image.source=https://github.com/microsoft/confidential-aci-dashboard
CMD ["python3", "/main.py"]
