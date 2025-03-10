FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16 AS build
RUN apk add --no-cache g++ linux-headers
COPY *.cpp *.c *.h ./
RUN g++ -static multicpu.cpp -Og -g -o multicpu && \
    g++ -static check_threads.cpp -Og -g -o check_threads && \
    gcc -static attestation_loop.c -Og -g -o attestation_loop

FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16
WORKDIR /var/www
RUN apk add --no-cache python3 fio bash sysbench stress-ng htop
COPY workload_*.sh server.py ./
COPY --from=build multicpu check_threads attestation_loop ./
ENV PORT=8000
CMD ["/bin/bash", "workload_tar.sh"]
