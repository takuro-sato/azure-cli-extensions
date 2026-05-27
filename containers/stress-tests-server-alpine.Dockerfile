FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16 AS build
RUN apk add --no-cache g++ linux-headers libc-dev
COPY stress_test_workloads/* ./
RUN g++ -static multicpu.cpp -Og -g -o multicpu && \
    g++ -static check_threads.cpp -Og -g -o check_threads && \
    gcc -static attestation_loop.c -Og -g -o attestation_loop && \
    g++ -static io_latency_bench.cpp -O3 -g -o io_latency_bench && \
    g++ -static threaded_add_numbers.cpp -O3 -g -o threaded_add_numbers

FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16
WORKDIR /var/www
RUN apk add --no-cache python3 python3-dev py3-pip fio bash sysbench stress-ng htop strace cifs-utils tcpdump jq && \
    pip3 install --no-cache-dir fastapi 'uvicorn[standard]'
COPY stress_test_workloads/workload_*.sh ./
COPY stress_test_workloads/io_latency_bench_like_ccf.py ./
COPY stress_test_workloads/stress_test_v2.py .
COPY server.py /server
COPY --from=build multicpu check_threads io_latency_bench attestation_loop threaded_add_numbers ./

EXPOSE 80
ENV PORT=80
LABEL org.opencontainers.image.source=https://github.com/microsoft/confidential-aci-dashboard
CMD ["/bin/bash", "workload_tar.sh"]
