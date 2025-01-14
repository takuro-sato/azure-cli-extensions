FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04 AS build
COPY *.cpp .
RUN apt update -y && \
    apt install -y g++ && \
    g++ -static multicpu.cpp -Og -g -o multicpu && \
    g++ -static check_threads.cpp -Og -g -o check_threads

FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
WORKDIR /var/www
RUN apt update -y && \
    apt install -y python3 fio bash sysbench curl stress-ng htop && \
    mkdir musl && \
    curl -sL 'https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox' -o musl/busybox
COPY workload_*.sh .
COPY --from=build multicpu check_threads .
ENV PORT=8000
CMD ["/bin/bash", "workload_tar.sh"]
