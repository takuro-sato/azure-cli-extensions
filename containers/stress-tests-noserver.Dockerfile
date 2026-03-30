ARG BASE_IMAGE=cacidashboardaci.azurecr.io/prebuilt-test-containers/stress-tests-server-alpine:latest
FROM ${BASE_IMAGE}
COPY stress_test_workloads/dump_to_output.sh /server
