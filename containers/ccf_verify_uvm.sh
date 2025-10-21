#!/usr/bin/env bash

set -o pipefail

SECURITY_CONTEXT=/security-context-*
if [ ! -d $SECURITY_CONTEXT ]; then
    echo "ERROR: $SECURITY_CONTEXT does not exist or is not a directory"
    exit 1
fi
# Usage documented at https://github.com/microsoft/CCF/releases/tag/ccf-7.0.0-dev4
/opt/ccf/bin/verify_uvm_attestation_and_endorsements \
    $SECURITY_CONTEXT/host-amd-cert-base64 \
    $SECURITY_CONTEXT/reference-info-base64 \
    $SECURITY_CONTEXT/security-policy-base64 \
    | tee /tmp/ccf_verify.log
status=$?
if [ $status -ne 0 ]; then
    echo "ERROR: ccf_verify_uvm_attestation_and_endorsements failed with status $status"
    exit $status
fi

if grep -q "Skipping test as this is not running in SEV-SNP" /tmp/ccf_verify.log; then
    echo "ERROR: not running in SEV-SNP"
    exit 1
fi

echo "ccf_verify_uvm: success"
