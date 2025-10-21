FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04 AS build
RUN apt update -y && apt install -y g++
COPY stress_test_workloads/* ./
RUN g++ -static multicpu.cpp -Og -g -o multicpu && \
    g++ -static check_threads.cpp -Og -g -o check_threads && \
    gcc -static attestation_loop.c -Og -g -o attestation_loop

FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
WORKDIR /var/www
RUN apt update -y && \
    apt install -y python3 python3-fastapi uvicorn fio bash sysbench curl stress-ng htop strace
COPY stress_test_workloads/workload_*.sh .
COPY server.py /server
COPY --from=build multicpu check_threads .

EXPOSE 80
ENV PORT=80
LABEL org.opencontainers.image.source=https://github.com/microsoft/confidential-aci-dashboard
CMD ["/bin/bash", "workload_tar.sh"]
