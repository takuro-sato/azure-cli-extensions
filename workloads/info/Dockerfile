FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
RUN apt-get update -y && apt-get install -y git make gcc libc-dev
RUN git clone --branch main --depth 1 --single-branch 'https://github.com/microsoft/confidential-sidecar-containers.git' skr && \
    cd skr/tools/get-snp-report && \
    make && \
    cp ./bin/* /usr/local/bin/
