FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04

RUN apt-get update && apt-get install -y python3

COPY sidecar_server.py .

CMD ["python3", "sidecar_server.py"]
