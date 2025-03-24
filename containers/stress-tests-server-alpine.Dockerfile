FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16 AS build
RUN apk add --no-cache g++ linux-headers libc-dev
COPY stress_test_workloads/* ./
RUN g++ -static multicpu.cpp -Og -g -o multicpu && \
    g++ -static check_threads.cpp -Og -g -o check_threads && \
    gcc -static attestation_loop.c -Og -g -o attestation_loop

FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16
WORKDIR /var/www
RUN apk add --no-cache python3 fio bash sysbench stress-ng htop
COPY stress_test_workloads/workload_*.sh ./
COPY server.py /server
COPY --from=build multicpu check_threads attestation_loop ./

EXPOSE 80
ENV PORT=80
LABEL org.opencontainers.image.source=https://github.com/microsoft/confidential-aci-dashboard
CMD ["/bin/bash", "workload_tar.sh"]
