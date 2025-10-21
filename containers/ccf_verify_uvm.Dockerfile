FROM mcr.microsoft.com/azurelinux/base/core:3.0
WORKDIR /usr/src

# build-essential >= 3.0 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# clang >= 18.1.2 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# cmake >= 3.21 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# curl-devel >= 7.68.0 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# libarrow.so.1500()(64bit) is needed by ccf_devel-7.0.0~dev4-1.x86_64
# libcxxabi-devel >= 18.1.2 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# libparquet.so.1500()(64bit) is needed by ccf_devel-7.0.0~dev4-1.x86_64
# libuv-devel >= 1.34.2 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# libuv.so.1()(64bit) is needed by ccf_devel-7.0.0~dev4-1.x86_64
# nghttp2-devel >= 1.40.0 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# ninja-build >= 1.11.1 is needed by ccf_devel-7.0.0~dev4-1.x86_64
# openssl-devel >= 3.3.0 is needed by ccf_devel-7.0.0~dev4-1.x86_64

RUN tdnf update -y && \
    tdnf install -y curl ca-certificates rpm \
    build-essential libcxxabi-devel clang cmake ninja-build make gcc gcc-c++ glibc-devel \
    libcurl-devel libuv-devel nghttp2-devel openssl-devel \
    libarrow-devel parquet-libs-devel \
    python3 python3-pip python3-setuptools python3-wheel
RUN curl -L 'https://github.com/microsoft/CCF/releases/download/ccf-7.0.0-dev4/ccf_devel_7.0.0_dev4_x86_64.rpm' -o 'ccf.rpm' && \
    rpm -i ccf.rpm

WORKDIR /
COPY ccf_verify_uvm.sh /ccf_verify_uvm.sh
COPY check_entrypoint.sh /check_entrypoint.sh
CMD ["/check_entrypoint.sh", "/ccf_verify_uvm.sh"]
