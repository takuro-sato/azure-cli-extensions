#!/usr/bin/bash

set -e

uname -a
if dmesg_output=$(dmesg 2>&1); then
    echo "$dmesg_output" | grep "Kernel command line" || true
    echo "$dmesg_output" | grep "Hyper-V: Host Build" || true
else
    echo "Skipping dmesg checks: $dmesg_output"
fi
echo Reference info SHA256SUM: $(base64 -d < /security-context-*/reference-info-base64 | sha256sum)
cat /proc/cpuinfo

has_err=0

if [ -n "$TEST_MANAGED_IDENTITY" ]; then
    echo "Testing managed identity..."
    tries=0
    identity_success=false
    while [ "$tries" -lt 5 ]; do
        tries=$((tries + 1))
        if timeout 10 curl --fail -s -H "Metadata: true" \
            "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
            -o /dev/null; then
            identity_success=true
            break
        fi
        echo "Managed identity attempt $tries failed, retrying..."
        sleep 5
    done
    if [ "$identity_success" = true ]; then
        echo "MANAGED_IDENTITY_TEST_SUCCESS=true"
    else
        echo "ERROR: Failed to retrieve a managed identity token after $tries attempts"
        has_err=1
    fi
fi

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
# Prod and Test DIDs share the same trust anchor (sha256 fingerprint) and
# differ only by the EKU OID embedded in the leaf signing cert:
#   Prod: ContainerPlat UVM EKU       1.3.6.1.4.1.311.76.59.1.2
#   Test: Windows code-signing (test) 1.3.6.1.4.1.311.10.3.13
PROD_UVM_DID='did:x509:0:sha256:I__iuL25oXEVFdTP_aBLx_eT1RPHbCQ_ECBQfYZpt9s::eku:1.3.6.1.4.1.311.76.59.1.2'
TEST_UVM_DID='did:x509:0:sha256:I__iuL25oXEVFdTP_aBLx_eT1RPHbCQ_ECBQfYZpt9s::eku:1.3.6.1.4.1.311.10.3.13'

# EXPECT_UVM_SIGNATURE selects which DID to validate against. Unset == "Prod"
# preserves the prior hardcoded behaviour for backward compatibility.
expected_signature="${EXPECT_UVM_SIGNATURE:-Prod}"
case "$expected_signature" in
    Prod) expected_did="$PROD_UVM_DID"; other_did="$TEST_UVM_DID"; other_label="Test" ;;
    Test) expected_did="$TEST_UVM_DID"; other_did="$PROD_UVM_DID"; other_label="Prod" ;;
    *)
        echo "ERROR: EXPECT_UVM_SIGNATURE must be 'Prod' or 'Test' (got '$expected_signature')"
        has_err=1
        expected_did=""
        ;;
esac

if [ -n "$expected_did" ]; then
    if sign1util check --in /tmp/reference-info --did "$expected_did"; then
        echo "UVM reference info signature OK (matches $expected_signature DID)"
    elif sign1util check --in /tmp/reference-info --did "$other_did"; then
        echo "ERROR: UVM reference info signature MISMATCH: expected $expected_signature signature but found $other_label signature"
        has_err=1
    else
        echo "ERROR: UVM reference info signature check failed against both Prod and Test DIDs"
        has_err=1
    fi
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
