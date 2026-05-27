---
name: add-aci-test
description: Step-by-step guide for adding a new ACI workload to this repo — creating the workloads/<name>/ directory (docker-compose.yml, .bicep, .bicepparam), the .github/workflows/workload-<name>.yml workflow, wiring it into .github/workflows/region.yml, and (optionally) adding a prebuilt image entry to containers/Makefile. Use whenever the user asks to "add a workload", "create a new test", "add a workflow for X", or copy an existing workload as a starting point. Covers gotchas: underscore↔hyphen filename mismatch, loadFileAsBase64 for pre-generated policies vs runtime policy gen, prebuilt-test-containers vs per-workload images.
---

# Adding a new ACI workload

## 1. Workload directory layout

Create `workloads/<name>/` with three core files. Either run `c-aci-testing aci create workloads/<name>` to scaffold them, or copy from a similar existing workload (`workloads/minimal` for the simplest confidential example; `workloads/skr-fixed-policy` for a fixed-policy / prebuilt-image example).

### `docker-compose.yml`

Defines the container image(s). Used by `c-aci-testing images pull` and `policies gen` to know which images to inspect.

Two shapes:

- **Pull a prebuilt image** (preferred — fastest workflow, deterministic policy):
  ```yaml
  services:
    main:
      image: $REGISTRY/$REPOSITORY/<image-name>:$TAG
  ```
  Use the shared `prebuilt-test-containers` repository and add a build target to [containers/Makefile](../../../containers/Makefile) — see step 4 below.

- **Build per run** (only when the image must be built fresh, e.g. it depends on something the test produces):
  ```yaml
  services:
    main:
      image: $REGISTRY/$REPOSITORY/<image-name>:$TAG
      build:
        context: .
        dockerfile: <name>.Dockerfile
  ```
  This is what `c-aci-testing target run` triggers. `workloads/skr` and `workloads/workload-sidecar-with-fragments` (Makefile-driven) are the existing examples.

`$REGISTRY`, `$REPOSITORY`, `$TAG` come from the workflow's `env:` block or `cacitesting.env` locally.

### `<name>.bicep`

ARM/Bicep for `Microsoft.ContainerInstance/containerGroups`. Key knobs:
- `osType`: `'Linux'` (default) or `'Windows'`
- `sku: 'Confidential'` — only for confidential workloads (omit for non-confidential)
- `confidentialComputeProperties.ccePolicy: ccePolicies.<name_with_underscores>` — only for confidential workloads
- `ipAddress` — only when the workload needs a public IP
- `containers[]` — image, resources, ports
- `output ids array = [containerGroup.id]` — required by `c-aci-testing aci deploy`

### `<name>.bicepparam`

Parameters file. `registry`, `repository`, `tag` get populated by `c-aci-testing` at policy gen / deploy time.

For confidential workloads, `ccePolicies` is an object with **one key matching the workload name with `-` replaced by `_`**:

- **Runtime-generated policy** (the common case — workflow runs `c-aci-testing policies gen` each run):
  ```bicep
  param ccePolicies = {
    my_workload: ''   // placeholder; populated by policies gen
  }
  ```

- **Pre-generated fixed policy** (when you want to commit the policy and skip generation at run time — see [workloads/skr-fixed-policy](../../../workloads/skr-fixed-policy/skr-fixed-policy.bicepparam)):
  ```bicep
  param ccePolicies = {
    my_workload: loadFileAsBase64('policy_my_workload.rego')
  }
  ```
  Generate the policy once locally with `c-aci-testing policies gen workloads/<name> --deployment-name test --policy-type generated`, then commit the resulting `policy_<name>.rego`. The image tags in `docker-compose.yml` / `.bicep` must then be **pinned to a stable tag** (not `latest`) so future pushes don't invalidate the committed policy.

  **Edge case:** `c-aci-testing` only auto-populates `registry`, `repository`, and `tag` in the `.bicepparam` from environment variables when `policies gen` runs. Fixed-policy workflows skip `policies gen` at run time, so those params stay empty and `aci deploy` fails. Hard-code them in the `.bicepparam` instead:
  ```bicep
  param registry='cacidashboardaci.azurecr.io'
  param tag='<your-pinned-tag>'   // matches the pinned tag from the workflow
  ```

## 2. Workflow YAML

Path: `.github/workflows/workload-<name>.yml`.

**Filename gotcha:** when the workload name contains underscores, the workflow filename sometimes converts them to hyphens and sometimes doesn't. Examples:
- `workloads/managed_identity` → `workload-managed-identity.yml`
- `workloads/ccf_verify_uvm` → `workload-ccf_verify_uvm.yml`

Match the convention of the closest existing example rather than picking a rule.

Use [`workload-minimal.yml`](../../workflows/workload-minimal.yml) as the standard template (simple confidential, no public IP), [`workload-info.yml`](../../workflows/workload-info.yml) for one with public IP, or [`workload-skr-fixed-policy.yml`](../../workflows/workload-skr-fixed-policy.yml) for the prebuilt-image / fixed-policy variant.

Every workflow has:

1. **Triggers**: `pull_request` and `push` on the relevant paths, `workflow_dispatch`, `workflow_call`. Always include `scripts/init_run.sh` and `scripts/install-c-aci-testing.sh` in the paths list.
2. **`env:` block**: copy from an existing workflow. Required vars include Kusto tracing config, `DEPLOYMENT_NAME`, `SUBSCRIPTION`, `RESOURCE_GROUP`, `REGISTRY`, `LOCATION`, `CLEANUP`, `POLICY_TYPE`, `RUN_FEATURES`, `TEST_TYPE`, `TEST_NAME`, `RUN_LINK`.
3. **Steps** (in order):
   - Checkout
   - Azure login (federated identity)
   - `./scripts/init_run.sh`
   - **Pull image** — `c-aci-testing images pull workloads/<name>` (skipped if `POLICY_TYPE == 'allow_all'`; skipped entirely for prebuilt-image workloads using `prebuilt-test-containers`)
   - Set parameters via `c-aci-testing aci param_set` (CPU, memory, etc.)
   - **Generate policy** — `c-aci-testing policies gen workloads/<name> --deployment-name $DEPLOYMENT_NAME` (skip for non-confidential and for fixed-policy workloads that use `loadFileAsBase64`)
   - **Deploy** — `./scripts/aci_deploy_traced.sh workloads/<name>`
   - Optional: wait for IP + curl (public-IP workloads only)
   - `./scripts/trace_run_result.sh ${{ job.status }}` in an `if: always()` step
   - Monitor container group (`if: always(), continue-on-error: true`)
   - Trace container states
   - Remove container group (gated on `CLEANUP != false`)

### `TEST_TYPE` values
- `aci` — Confidential ACI workload (Linux)
- `aci-non-confidential` — Non-confidential ACI workload (Linux or Windows)

### `RUN_FEATURES`
Comma-separated tags for the run: `public_ip`, `vnet`, `managed_identity`, `big_containers`, etc.

## 3. Wire into `region.yml`

Add a job in [.github/workflows/region.yml](../../workflows/region.yml) calling your new workflow via `uses: ./.github/workflows/workload-<name>.yml`. The jobs run sequentially via `needs:` — insert at a sensible spot and update the `needs:` of the next job in the chain. Gate on `!cancelled()`, and add the public-IP region filter (`!contains(vars.REGIONS_WITH_PROBLEMATIC_PUBLIC_IP, format(',{0},', inputs.location))`) if the workload uses a public IP.

Use a `matrix` over `policy_type: ['generated', 'debug', 'allow_all']` when it makes sense; omit the matrix for fixed-policy workloads or non-confidential-only workloads.

## 4. Optional: prebuilt image in `containers/`

If the workload uses a prebuilt image from `prebuilt-test-containers`, add it to [containers/Makefile](../../../containers/Makefile):

1. Drop the `Dockerfile` (and any source files) into [containers/](../../../containers/).
2. Add a `build_<name>` target, add `<name>` to `IMAGES` (so push / manifest merge picks it up), and add the target to the `build` aggregate. Add it to `.PHONY` too.
3. Build and push the image: `make -C containers build_<name> push_arch IMAGES_TO_PUSH=<name>` (or do it manually with `docker buildx` if you only want to push the one image — the Makefile's `push_arch` pushes all `IMAGES_TO_PUSH`).
4. If using a fixed policy, **pin a non-`latest` tag** (e.g. `TAG: <workload-name>` in the workflow env) and add a comment in the workflow explaining why, so future pushes to `:latest` don't break the committed policy.

## 5. Validate before pushing

- Bicepparam compiles: `bash -c '. cacitesting.env && export TAG=<tag> && export REPOSITORY=<repo> && az bicep build-params --file workloads/<name>/<name>.bicepparam --outfile /tmp/out.json'`
- Policy generation works (or, for fixed-policy, the file is committed and `loadFileAsBase64` resolves it)
- Workflow yaml parses (`actionlint` if installed)
