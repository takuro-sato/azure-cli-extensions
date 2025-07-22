FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends python3 python3-fastapi uvicorn curl tcpdump net-tools bind9-host ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY *.sh *.py /usr/local/bin/
EXPOSE 80
ENV PORT=80
LABEL org.opencontainers.image.source=https://github.com/microsoft/confidential-aci-dashboard
CMD ["bash", "-c", "( sleep 0.2; curl_from_container.sh ) & disown; server.py"]
