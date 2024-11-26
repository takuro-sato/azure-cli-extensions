FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04

RUN apt-get update && apt-get install -y curl

COPY primary_startup.sh .
CMD ["bash", "primary_startup.sh"]
