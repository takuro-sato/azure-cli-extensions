FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16 AS build
COPY multicpu.cpp .
RUN apk add --no-cache g++ linux-headers && \
    g++ -static multicpu.cpp -Og -g -o multicpu

FROM mcr.microsoft.com/mirror/docker/library/alpine:3.16
WORKDIR /var/www
RUN apk add --no-cache python3 fio bash sysbench stress-ng htop
COPY workload_*.sh dump_to_output.sh ./
COPY --from=build multicpu ./
ENV PORT=8000
CMD ["/bin/bash", "workload_tar.sh"]
