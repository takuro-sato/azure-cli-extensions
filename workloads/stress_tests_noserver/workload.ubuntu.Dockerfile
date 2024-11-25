FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04 AS build
COPY multicpu.cpp .
RUN apt update -y && \
    apt install -y g++ && \
    g++ -static multicpu.cpp -Og -g -o multicpu

FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
WORKDIR /var/www
RUN apt update -y && \
    apt install -y python3 fio bash sysbench curl stress-ng htop && \
    mkdir musl && \
    curl -sL 'https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox' -o musl/busybox
COPY workload_*.sh dump_to_output.sh .
COPY --from=build multicpu .
ENV PORT=8000
CMD ["/bin/bash", "workload_tar.sh"]
