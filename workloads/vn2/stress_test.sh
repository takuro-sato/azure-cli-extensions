#!/usr/bin/bash

if [ -z "$CPU" ]; then
  CPU=4
fi
if [ -z "$MEMORY_IN_GB" ]; then
  MEMORY_IN_GB=16
fi
if [ -z "$POLICY_TYPE" ]; then
  POLICY_TYPE=generated
fi

SCRIPTS_DIR="$(realpath "$(dirname $0)/../../scripts")"
TRACE_SCRIPT="$SCRIPTS_DIR/tracing/trace_step.py"

set -ex
cd workloads/stress_tests
rm -f stress_tests.yaml
c-aci-testing images pull .
c-aci-testing aci param_set . --parameter totalCpus=$CPU
c-aci-testing aci param_set . --parameter totalMemoryGB=$MEMORY_IN_GB
c-aci-testing vn2 generate_yaml .
c-aci-testing vn2 policygen --policy-type $POLICY_TYPE .

echo
echo "Generated YAML file:"
cat stress_tests.yaml
echo

set +ex

echo "Deploying..."
MONITOR_SECS=20 ../vn2/vn2-test-single-yaml-deploy.sh stress_tests.yaml
if [ $? -ne 0 ]; then
  exit 1
fi

# The following mirrors /.github/workflows/workload-stress-tests.yml

echo "Get IP address"
$TRACE_SCRIPT --start "Get IP address"
# ip_address="$(c-aci-testing vn2 get-ip)"
../vn2/update-waf.sh "$RESOURCE_GROUP" "$AKS_CLUSTER_NAME" "svc/$DEPLOYMENT_NAME"
if [ $? -ne 0 ]; then
  echo "Failed to update WAF"
  $TRACE_SCRIPT --complete --strict --err "Failed to update WAF"
  exit 1
fi
ip_address=$(cat ../vn2/.waf-frontend-ip.txt)
if [ $? -ne 0 ] || [ -z "$ip_address" ]; then
  echo "Failed to get IP address from WAF update script"
  $TRACE_SCRIPT --complete --strict --err "Failed to get IP address from WAF update script"
  exit 1
fi

echo "Curl Server"
$SCRIPTS_DIR/curl_check_with_retry.sh "http://$ip_address"
if [ $? -ne 0 ]; then
  echo "Curl failed"
  exit 1
fi

echo 'Let container run for 1min and test again'
sleep 100
$TRACE_SCRIPT --start 'Curl Server after 1min'
timeout -s INT 1m curl --fail-with-body http://$ip_address
if [ $? -ne 0 ]; then
  echo "Curl failed after 1min"
  $TRACE_SCRIPT --complete --strict --err "Curl failed after 1min"
  exit 1
fi

echo 'Get container output'
$TRACE_SCRIPT --start 'Get container output'
rm -f output.log
c-aci-testing vn2 logs | tee output.log
if [ $? -ne 0 ]; then
  echo "Failed to get container output"
  $TRACE_SCRIPT --complete --strict --err "Failed to get container output"
  exit 1
fi

echo "Parse container output"
$SCRIPTS_DIR/parse_container_output.py --fail-on-error --error-count-threshold 15 output.log

echo "Check correct kernel version"
$SCRIPTS_DIR/check_uname_in_output.sh output.log

echo "Check dmesg"
$TRACE_SCRIPT --start 'Check dmesg'
dmesg_file="dmesg.log"

timeout -s INT 1m curl --fail-with-body http://$ip_address/dmesg.log -o $dmesg_file
if [ $? -ne 0 ]; then
  echo "Failed to get dmesg"
  cat $dmesg_file
  $TRACE_SCRIPT --complete --strict --err "Failed to get dmesg"
  exit 1
fi

# will call trace --complete
$SCRIPTS_DIR/_check_dmesg.sh "$dmesg_file"

if [ "$CLEANUP" != false ]; then
  c-aci-testing vn2 remove
fi
