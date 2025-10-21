#!/usr/bin/bash

set -e

uname -a
dmesg | grep "Kernel command line"
dmesg | grep "Hyper-V: Host Build"
echo Reference info SHA256SUM: $(base64 -d < /security-context-*/reference-info-base64 | sha256sum)
cat /proc/cpuinfo

has_err=0

set +e
if [ ! -e /dev/sev-guest ]; then
    echo "ERROR: /dev/sev-guest not found"
    echo "Skipping report generation"
    has_err=1
else
    echo "raw report:"
    get-snp-report
    if [ $? -ne 0 ]; then
        echo "ERROR: get-snp-report failed"
        exit 1
    fi
    echo
    echo "snp-report:"
    verbose-report
    if [ $? -ne 0 ]; then
        echo "ERROR: verbose-report failed"
        exit 1
    fi
fi
set -e

if [ ! -d /security-context-* ]; then
    echo "ERROR: /security-context-* not found"
    exit 1
fi

base64 -d < /security-context-*/reference-info-base64 > /tmp/reference-info
echo "UVM reference info:"
sign1util print -in /tmp/reference-info | tee /tmp/refinfo.txt
if ! sign1util check \
    --in /tmp/reference-info \
    --did 'did:x509:0:sha256:I__iuL25oXEVFdTP_aBLx_eT1RPHbCQ_ECBQfYZpt9s::eku:1.3.6.1.4.1.311.76.59.1.2';
    then
    echo "ERROR: UVM reference info signature check failed"
    has_err=1
fi
gawk -e '/^payload:$/ { payload=1; next } payload { print }' /tmp/refinfo.txt > /tmp/ref-payload.json

set +e
PARSED_UVM_REF="$(jq . -c /tmp/ref-payload.json)"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to parse UVM reference info JSON"
    has_err=1
else
    echo "UVM Reference info parsed: ${PARSED_UVM_REF}"
fi

maybe_require_host_amd_cert=""

if [ -n "$EXPECT_HOST_AMD_CERT" ]; then
    maybe_require_host_amd_cert="--require-host-amd-cert"
fi

/sctx_schema/check.py --reference-payload /tmp/ref-payload.json $maybe_require_host_amd_cert || has_err=1

if [ $has_err -ne 0 ]; then
    exit 1
fi

echo "info: success"
