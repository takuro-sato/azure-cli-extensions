ARG BASE_IMAGE=ghcr.io/microsoft/confidential-aci-dashboard/test-containers/stress-tests-server-alpine:latest
FROM ${BASE_IMAGE}
COPY stress_test_workloads/dump_to_output.sh /server
