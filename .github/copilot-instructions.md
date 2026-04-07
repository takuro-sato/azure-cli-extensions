# Copilot Instructions

## Structure of Workloads

Each workload lives under `workloads/<name>/` and contains at least these three core files (extra assets such as Dockerfiles or helper scripts may also live in the workload directory):

1. **`docker-compose.yml`** — Defines the container image(s) used by the workload. This is used by `c-aci-testing images pull` to pull images locally (needed for policy generation) and by `c-aci-testing policies gen` to determine which images need policies.  For some tests (e.g. skr and workloads/workload-sidecar-with-fragments, although the latter doesn't actually use the standard c-aci-testing structure and instead use a Makefile), the images might be built for each test run, in which case this docker-compose.yml contains build: dockerfile: ... instead of an image reference.  The docker-compose.yml file may use environment variables (e.g., `${REGISTRY}`, `${REPOSITORY}`, `${TAG}`) that are set in the GitHub Actions workflow or locally in `cacitesting.env`.

2. **`<name>.bicep`** — ARM/Bicep template that defines the Azure Container Instance (ACI) container group resource (`Microsoft.ContainerInstance/containerGroups`). Key properties include:
   - `osType`: default to `'Linux'` but can also be set to `'Windows'`
   - `sku`: `'Confidential'` (only for confidential workloads)
   - `confidentialComputeProperties.ccePolicy`: references the generated security policy (only for confidential workloads)
   - `ipAddress`: present only when the container needs a public IP (e.g., server/IIS workloads)
   - `containers`: array of container definitions with image, resource requests, and ports
   - The `output ids array` is expected by `c-aci-testing aci deploy`

3. **`<name>.bicepparam`** — Bicep parameters file that uses the `.bicep` file. Contains default parameter values. For confidential workloads, includes a `ccePolicies` object with a single field with the key being the name of the workload (but any - is replaced with _) and the value being an empty string placeholder that gets populated during policy generation.

Some parameters are also populated by c-aci-testing by default at either policy generation or deployment time:
- registry: set to the REGISTRY environment variable
- repository: set to the REPOSITORY environment variable
- tag: set to the TAG environment variable

### Workflow yaml structure

Each workload has a corresponding GitHub Actions workflow under `.github/workflows/`, usually named with a `workload-...yml` prefix, but the filename is not always a direct transformation of the workload directory name. In particular, workload names containing underscores sometimes map to hyphens in the workflow filename and sometimes keep underscores. For example, `workloads/managed_identity` uses `.github/workflows/workload-managed-identity.yml`, while `workloads/ccf_verify_uvm` uses `.github/workflows/workload-ccf_verify_uvm.yml`. When creating a new workflow, follow the naming pattern used by the closest existing example rather than assuming a single underscore/hyphen conversion rule. Every workflow follows the same general pattern:

1. **Triggers**: `pull_request` and `push` (on paths related to the workload and scripts), `workflow_dispatch`, and `workflow_call` (for scheduled multi-region test runs)
2. **Environment variables**: Kusto tracing config, deployment name, Azure subscription/RG/registry info, location, CPU/memory, cleanup flag, policy type, `RUN_FEATURES`.  Copy this from an existing workflow and modify as needed when creating a new one.
3. Workflow steps (reference existing .github/workflows/workload-info.yml and .github/workflows/workload-minimal.yml when creating a new workflow):
   - Checkout code
   - Azure login (federated identity)
   - Initialize run (install dependencies + start tracing)
   - Pull image (for policy generation; skipped if `POLICY_TYPE == 'allow_all'`)
   - Set parameters (CPU, memory)
   - Generate security policy (unless non-confidential)
   - Deploy container group using scripts/aci_deploy_traced.sh
   - Wait for IP + curl (only for some workload with public IP)
   - Report result to tracing Kusto
   - Monitor container group
   - Get container states
   - Remove container group (unless cleanup is disabled)

### TEST_TYPE values

- `aci` — Confidential ACI workload (Linux)
- `aci-non-confidential` — Non-confidential ACI workload (Linux or Windows)

### RUN_FEATURES

Comma-separated string of feature flags for the run: public_ip, vnet, managed_identity, big_containers etc

## How c-aci-testing Works

[c-aci-testing](https://github.com/microsoft/confidential-aci-testing) is a CLI tool (`c-aci-testing`) for testing Confidential (and non-confidential) containers on Azure Container Instances.

### Installation

User's machine should already have this installed. If not, prompt the user to install via scripts/install-c-aci-testing.sh.

### Key commands

| Command | Purpose |
|---------|---------|
| `c-aci-testing aci create workloads/<name>` | Create a template workload directory (docker-compose.yml, .bicep, .bicepparam). **Does not** create the GitHub Actions workflow YAML — you must create that manually following existing examples. |
| `c-aci-testing images pull workloads/<name>` | Pull container images defined in docker-compose.yml locally. Required before policy generation. |
| `c-aci-testing images build workloads/<name>` | Build container images from Dockerfiles in docker-compose.yml. |
| `c-aci-testing images push workloads/<name>` | Push built images to the configured ACR. |
| `c-aci-testing policies gen workloads/<name>` | Generate security policies (`.rego` files) for the workload. Internally calls `az confcom` to produce the CCE policy. For C-WCOW workloads, this **must** run on a Windows host with Windows Docker. |
| `c-aci-testing aci param_set workloads/<name> --parameter key=value` | Set a parameter in the `.bicepparam` file. |
| `c-aci-testing aci deploy workloads/<name>` | Deploy the container group to ACI using the Bicep template. Supports `--timeout`, `--deploy-output-file`, `--deployment-name`. |
| `c-aci-testing aci monitor --deployment-name <name>` | Monitor container logs. Supports `--follow` to wait for container termination. |
| `c-aci-testing aci remove --deployment-name <name>` | Remove the deployed container group. |
| `c-aci-testing aci get ips --deployment-name <name>` | Get the public IP address(es) of the container group. |
| `c-aci-testing aci get ids --deployment-name <name>` | Get resource IDs of deployed resources. |

### Workflow for Confidential Containers (Linux or Windows)

1. **Pull images** — `c-aci-testing images pull` downloads images so `az confcom` can inspect their layers
2. **Generate policy** — `c-aci-testing policies gen` calls `az confcom` to generate a Rego security policy. The policy is base64-encoded and injected into the `.bicepparam` file's `ccePolicies` parameter
3. **Deploy** — `c-aci-testing aci deploy` submits the Bicep template to ARM, which creates the container group with the embedded CCE policy

### Workflow for Non-Confidential Containers

Same as above but skip the policy generation step. The Bicep template omits `sku: 'Confidential'` and `confidentialComputeProperties`.

### Tracing

This repo uses a Kusto-based tracing system (`scripts/tracing/`) to record test run metadata, step timings, and results. The tracing scripts are Python and work cross-platform. They ingest data into a Kusto table (`CACITestStepTrace`) via the Azure Data Explorer SDK.

#### How it works

The system uses a **state file** (`~/.cacitesting-tracing-state.json`) to track the current run and step. This avoids passing state between workflow steps explicitly.

1. **`new_run.py`** — Called once at the start of a workflow (via `scripts/init_run.sh`). It generates a unique run ID (`UniqueRunId`) and writes initial run metadata (deployment name, location, test type, etc.) to the state file. It also traces an `Init` step as `Started`.

2. **`trace_step.py`** — Called throughout the workflow to trace individual steps. It has two modes:
   - `--start '<step name>'`: Traces the start of a new step. If a previous step is still open (not completed), it auto-completes that step first (assuming success). The `STEP_PREFIX` environment variable, if set, is prepended to the step name (e.g., `stress-4cpu-16gb: Pull image`).
   - `--complete`: Marks the current open step as completed. Optional flags:
     - `--err "<message>"`: Attach an error message (marks the step as failed).
     - `--output key1=value1 key2=value2`: Attach key-value output data.
     - `--output-from-stdin`: Read a JSON object from stdin as the output data.
     - `--strict`: Fail if there is no open step to complete (default: warn only).
   - If `KUSTO_CONNECTION_STRING` is not set, `trace_step.py` prints a skip message to stderr and exits successfully (allows local runs without Kusto).

3. **`trace_run_result.sh`** — Convenience wrapper called in `if: always()` steps. Takes the GitHub job status (`success`/`failure`/`cancelled`) and calls `trace_step.py --complete` with the appropriate error message. This ensures any still-open step gets closed.

#### Required environment variables

Tracing requires these environment variables (set in the workflow `env:` block):
- `KUSTO_CONNECTION_STRING` — Kusto cluster connection string (from secrets)
- `KUSTO_DATABASE` — Kusto database name (from secrets)
- `KUSTO_TABLE` — Table name (typically `CACITestStepTrace`)
- `DEPLOYMENT_NAME` — Used as the deployment identifier in traces
- `LOCATION`, `RESOURCE_GROUP`, `TEST_TYPE`, `TEST_NAME`, `RUN_LINK` — Run metadata

#### Usage patterns in workflows

```yaml
# Start a new traced step
- run: ./scripts/tracing/trace_step.py --start 'My step name'

# Complete it with output
- run: ./scripts/tracing/trace_step.py --complete --strict --output key1=value1

# Complete with JSON output from stdin
- run: jq -Rs '{log: .}' output.log | ./scripts/tracing/trace_step.py --complete --strict --output-from-stdin

# Complete with error
- run: ./scripts/tracing/trace_step.py --complete --strict --err "Something failed"

# Auto-close any open step based on job status (in if: always() step)
- run: ./scripts/trace_run_result.sh ${{ job.status }}
```

## Running Tests Locally

Before running any `c-aci-testing` commands locally, you must source the environment file `cacitesting.env` to set required environment variables (subscription, resource group, registry, location, etc.):

```bash
. cacitesting.env
c-aci-testing images pull workloads/minimal
c-aci-testing policies gen workloads/minimal
c-aci-testing aci deploy workloads/minimal
```

**Note:** `cacitesting.env` uses bash `export` syntax and must be sourced from a bash-compatible shell. If you are using a non-bash shell (e.g., fish), you must either:
- Run commands via bash explicitly: `bash -c '. cacitesting.env; c-aci-testing ...'`
- Switch to a bash shell first: `bash` then `. cacitesting.env`

## Adding a New VN2 Test Case

VN2 tests run workloads on Azure Kubernetes Service (AKS) via the Virtual Node 2 (VN2) infrastructure. All VN2 test cases are defined in `.github/workflows/vn2-region.yml` and executed sequentially within a single job.

### Steps to add a new VN2 test case

1. **Ensure you have a workload directory** under `workloads/<name>/` with the core files (`docker-compose.yml`, `<name>.bicep`, `<name>.bicepparam`). The bicep file should be compatible with VN2 deployment (i.e., it must work with `c-aci-testing vn2 generate_yaml` and `c-aci-testing vn2 policygen`).

2. **Create a VN2 test script** (if needed). For simple workloads, you can use the generic `workloads/vn2/vn2-test-run.sh` script directly from the workflow step. For complex tests that need custom orchestration (e.g., multi-replica coordination, custom curl checks), create a dedicated script under `workloads/vn2/<test_name>.sh`. See `workloads/vn2/stress_test.sh` as an example.

3. **Add a test case step in `.github/workflows/vn2-region.yml`**. Insert the following blocks before the final `Report result` / `Download vn2 logs` steps, after the last existing test case:

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
             DEPLOYMENT_NAME: <your-deployment-name>  # must not contain underscores
             STEP_PREFIX: <your-step-prefix>
             REGISTRY: cacidashboardaci.azurecr.io
             REPOSITORY: <your-repository>
             TAG: latest
           run: |
             # For simple workloads using vn2-test-run.sh:
             MONITOR_SECS=60 ./workloads/vn2/vn2-test-run.sh workloads/<name>
             ./scripts/parse_container_output.py --fail-on-error output.log

             # Or for custom scripts:
             ./workloads/vn2/<your_script>.sh
   ```

4. **Key conventions to follow:**
   - Always add a `Re-log into Azure` step before your test case (Azure tokens expire during long runs).
   - Use `if: ${{ !cancelled() && steps.vn2_deploy.outcome == 'success' }}` to skip the test if VN2 Helm deployment failed.
   - Pod names (DEPLOYMENT_NAME) cannot contain underscores — use hyphens instead.
   - Set `STEP_PREFIX` to match the test name for tracing.
   - If the workload needs images from the project registry, set `REGISTRY`, `REPOSITORY`, and `TAG`.
   - For workloads needing managed identity, set `AKS_RESOURCE_GROUP=$RESOURCE_GROUP` then override `RESOURCE_GROUP=c-aci-dashboard`.

5. **If your test needs custom orchestration**, create a script under `workloads/vn2/` that:
   - Calls `c-aci-testing images pull .` to pull images
   - Calls `c-aci-testing vn2 generate_yaml .` and `c-aci-testing vn2 policygen .` to generate the deployment YAML with policy
   - Uses `../../workloads/vn2/vn2-test-single-yaml-deploy.sh <yaml_file>` to deploy
   - Uses `kubectl` to interact with pods (e.g., `kubectl exec`, `kubectl logs`, `kubectl get pods`)
   - Calls `c-aci-testing vn2 remove` for cleanup
   - Uses `$SCRIPTS_DIR/tracing/trace_step.py` for tracing steps

6. **Test manually** by running the VN2 workflow with `workflow_dispatch`, specifying the target location and AKS cluster.
