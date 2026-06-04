#!/usr/bin/env bash

# Stop and remove the confidential WCOW pod named "$STEP_PREFIX" on the test VM.
#
# Each c-aci-testing `vm runc` deploys a distinctly-named pod (named after the
# workload prefix) and its generated run.ps1 only tears down a pod of that same
# name before (re)starting it. Pods from *other* workloads are left resident as
# idle "Ready" sandboxes. On confidential WCOW every sandbox reserves a large
# fixed UVM memory allocation, so letting all five workloads accumulate
# exhausts the single DC8as_cc_v5 VM and the next pod fails to start with
# "Not enough memory resources are available to complete this operation".
#
# We therefore tear down each pod once we are done asserting on it, keeping at
# most one confidential WCOW UVM resident at a time. Best-effort: a teardown
# hiccup must not fail the run, so we always exit 0.

set -e
./scripts/tracing/trace_step.py --start 'Stop pod'
set +e

c-aci-testing vm exec --deployment-name "$DEPLOYMENT_NAME" "\$id = (C:/ContainerPlat/azcrictl.exe pods --name ${STEP_PREFIX} -q); if (\$id) { C:/ContainerPlat/azcrictl.exe stopp \$id; C:/ContainerPlat/azcrictl.exe rmp \$id; Write-Output 'Stopped pod ${STEP_PREFIX}' } else { Write-Output 'Pod ${STEP_PREFIX} not found; nothing to stop' }"

exit 0
