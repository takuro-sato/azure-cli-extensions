# Copilot Instructions

## Repo overview

This repo is a dashboard / test harness for Confidential ACI. Tests are organized as **workloads** under `workloads/<name>/`, each driven by a corresponding GitHub Actions workflow under `.github/workflows/workload-<name>.yml`. The `region.yml` workflow sequences these per-region runs across the matrix of supported Azure regions.

The repo also has a **VN2** path that runs workloads on AKS instead of ACI; those test cases are all sequential steps inside `.github/workflows/vn2-region.yml`.

Tooling:
- [c-aci-testing](https://github.com/microsoft/confidential-aci-testing) (`c-aci-testing` CLI) drives image build/pull, CCE policy generation, ACI/VN2 deployment, and cleanup.
- `scripts/tracing/` ingests step timings and results into a Kusto table (`CACITestStepTrace`) so runs are observable.
- `containers/` builds shared prebuilt test images (pushed to `cacidashboardaci.azurecr.io/prebuilt-test-containers/...`) consumed by many workloads.

## Workload structure (at a glance)

Each `workloads/<name>/` directory contains at minimum:

- `docker-compose.yml` — the image(s) the workload uses. Either references a prebuilt image or contains `build: dockerfile: ...` to build per run.
- `<name>.bicep` — ARM/Bicep `Microsoft.ContainerInstance/containerGroups` definition. Confidential workloads set `sku: 'Confidential'` and reference `ccePolicies.<name_underscored>`.
- `<name>.bicepparam` — parameter file. `registry`/`repository`/`tag` are populated by `c-aci-testing`; `ccePolicies` is either populated at run time by `policies gen` or, for fixed-policy workloads, via `loadFileAsBase64(...)` against a committed `.rego` file.

> **Adding a new workload?** Use the **add-workload** skill — it covers directory layout, the workflow yaml template, `region.yml` wiring, the prebuilt-image / `containers/Makefile` path, and the underscore↔hyphen / fixed-policy / pinned-tag gotchas.
>
> **Adding a VN2 test case?** Use the **add-vn2-test** skill.

## `c-aci-testing` quick reference

User's machine should already have it installed. If not, install via `scripts/install-c-aci-testing.sh`.

| Command | Purpose |
|---------|---------|
| `c-aci-testing aci create workloads/<name>` | Scaffold a new workload directory (does NOT create the workflow yaml). |
| `c-aci-testing images pull workloads/<name>` | Pull images locally (needed before policy generation). |
| `c-aci-testing images build workloads/<name>` | Build images per `docker-compose.yml`. |
| `c-aci-testing images push workloads/<name>` | Push built images to the configured ACR. |
| `c-aci-testing policies gen workloads/<name>` | Generate CCE policy via `az confcom`. C-WCOW workloads need a Windows host. |
| `c-aci-testing aci param_set workloads/<name> --parameter key=value` | Set a value in `.bicepparam`. |
| `c-aci-testing aci deploy workloads/<name>` | Deploy the container group. |
| `c-aci-testing aci monitor --deployment-name <name>` | Tail container logs (`--follow` to wait for termination). |
| `c-aci-testing aci remove --deployment-name <name>` | Delete the container group. |
| `c-aci-testing aci get ips --deployment-name <name>` | Public IPs of the container group. |
| `c-aci-testing aci get ids --deployment-name <name>` | Resource IDs of deployed resources. |

End-to-end flow for a confidential workload: `images pull` → `policies gen` (skip for non-confidential / fixed-policy) → `aci deploy`.

## Running tests locally

Source `cacitesting.env` first to populate subscription / RG / registry / location:

```bash
. cacitesting.env
c-aci-testing images pull workloads/minimal
c-aci-testing policies gen workloads/minimal
c-aci-testing aci deploy workloads/minimal
```

`cacitesting.env` uses bash `export` syntax. From fish, either run via bash explicitly (`bash -c '. cacitesting.env; c-aci-testing ...'`) or `exec bash` first.

## Tracing (`scripts/tracing/`)

Cross-platform Python scripts that report step timings to Kusto. State lives in `~/.cacitesting-tracing-state.json` so steps don't need to thread state through each other.

- `new_run.py` — called once at workflow start via `scripts/init_run.sh`. Generates `UniqueRunId`, records run metadata, opens an `Init` step.
- `trace_step.py`:
  - `--start '<name>'` — start a step; auto-completes any still-open step (assumes success). `STEP_PREFIX` env var, if set, is prepended.
  - `--complete` — close the current step. Flags: `--err "<msg>"` (mark failed), `--output k=v ...`, `--output-from-stdin` (JSON object on stdin), `--strict` (fail if no open step).
  - No-ops (with stderr message) when `KUSTO_CONNECTION_STRING` is unset, so local runs still work.
- `trace_run_result.sh` — convenience for `if: always()`: takes the job status and closes any open step appropriately.

Required env in workflows: `KUSTO_CONNECTION_STRING`, `KUSTO_DATABASE`, `KUSTO_TABLE`, `DEPLOYMENT_NAME`, `LOCATION`, `RESOURCE_GROUP`, `TEST_TYPE`, `TEST_NAME`, `RUN_LINK`.

Typical usage in a workflow step:

```yaml
- run: ./scripts/tracing/trace_step.py --start 'My step name'
- run: ./scripts/tracing/trace_step.py --complete --strict --output key=value
# JSON output from stdin:
- run: jq -Rs '{log: .}' output.log | ./scripts/tracing/trace_step.py --complete --strict --output-from-stdin
# Failure:
- run: ./scripts/tracing/trace_step.py --complete --strict --err "Something failed"
# Always close at end of job:
- run: ./scripts/trace_run_result.sh ${{ job.status }}
```
