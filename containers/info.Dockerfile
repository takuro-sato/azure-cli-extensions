FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04
RUN apt-get update -y && \
    apt-get install -y git make gcc libc-dev curl gawk jq procps python3-jsonschema && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /
RUN git clone -q --branch main --depth 1 --single-branch \
        'https://github.com/microsoft/confidential-sidecar-containers.git' skr
RUN cd skr/tools/get-snp-report && make && cp ./bin/* /usr/local/bin/

ARG SIGN1UTIL_VERSION="1.4.0"
RUN curl -sL \
    "https://github.com/microsoft/cosesign1go/releases/download/v${SIGN1UTIL_VERSION}/sign1util" \
    -o "/usr/local/bin/sign1util" && \
    chmod +x "/usr/local/bin/sign1util"

COPY info_check.sh /info_check.sh
COPY check_entrypoint.sh /check_entrypoint.sh

# Avoid naming it security_context_...
COPY security_context_schema /sctx_schema

CMD ["/check_entrypoint.sh", "/info_check.sh"]
