---
name: add-vn2-test
description: Step-by-step guide for adding a new VN2 (Virtual Node 2 / AKS) test case. VN2 tests run workloads on AKS and all live as sequential steps in .github/workflows/vn2-region.yml. Use when the user asks to "add a VN2 test", "add a test case to vn2-region", or wants to run an existing workload on AKS instead of ACI.
---

# Adding a new VN2 test case

VN2 tests run workloads on Azure Kubernetes Service (AKS) via the Virtual Node 2 infrastructure. All VN2 test cases are defined as sequential steps in `.github/workflows/vn2-region.yml`, inside a single job.

## 1. Workload directory

Reuse an existing `workloads/<name>/` or create a new one (see the **add-workload** skill). The bicep file must be compatible with `c-aci-testing vn2 generate_yaml` and `c-aci-testing vn2 policygen`.

## 2. Test script

- **Simple workloads**: use the generic `workloads/vn2/vn2-test-run.sh` directly from the workflow step.
- **Complex orchestration** (multi-replica coordination, custom curl checks, etc.): add `workloads/vn2/<test_name>.sh`. Use `workloads/vn2/stress_test.sh` as a reference. A custom script should:
  - `c-aci-testing images pull .` to pull images
  - `c-aci-testing vn2 generate_yaml .` + `c-aci-testing vn2 policygen .` to produce the deployment yaml with policy
  - `../../workloads/vn2/vn2-test-single-yaml-deploy.sh <yaml_file>` to deploy
  - `kubectl` for interacting with pods (`exec`, `logs`, `get pods`)
  - `c-aci-testing vn2 remove` for cleanup
  - `$SCRIPTS_DIR/tracing/trace_step.py` for tracing each phase

## 3. Add a step in `vn2-region.yml`

Insert before the final `Report result` / `Download vn2 logs` steps, after the last existing test case. Each test case is two steps — re-login plus the test itself:

```yaml
      - name: Re-log into Azure
        if: ${{ !cancelled() && steps.vn2_deploy.outcome == 'success' }}
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID_ACI }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.SUBSCRIPTION_ACI }}

      - name: 'Test case - <your-test-name>'
        if: ${{ !cancelled() && steps.vn2_deploy.outcome == 'success' }}
        env:
          DEPLOYMENT_NAME: <your-deployment-name>  # NO underscores
          STEP_PREFIX: <your-step-prefix>
          REGISTRY: cacidashboardaci.azurecr.io
          REPOSITORY: <your-repository>
          TAG: latest
        run: |
          # Simple:
          MONITOR_SECS=60 ./workloads/vn2/vn2-test-run.sh workloads/<name>
          ./scripts/parse_container_output.py --fail-on-error output.log

          # Or, custom:
          # ./workloads/vn2/<your_script>.sh
```

## 4. Conventions

- **Always re-login first.** Azure tokens expire during long runs.
- **Gate on `!cancelled() && steps.vn2_deploy.outcome == 'success'`** so failed Helm deployments skip the rest.
- **Pod names (DEPLOYMENT_NAME) must not contain underscores** — use hyphens.
- Set `STEP_PREFIX` to match the test name (used by the tracing system to prefix step names).
- For workloads pulling from the project registry, set `REGISTRY`, `REPOSITORY`, `TAG` in the step env.
- For workloads needing managed identity: set `AKS_RESOURCE_GROUP=$RESOURCE_GROUP` then override `RESOURCE_GROUP=c-aci-dashboard`.

## 5. Test it

Trigger `vn2-region.yml` via `workflow_dispatch`, supplying the target location and AKS cluster.
