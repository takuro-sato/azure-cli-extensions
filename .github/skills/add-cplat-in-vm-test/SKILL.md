---
name: add-cplat-in-vm-test
description: Step-by-step guide for adding a workload that runs a Linux container inside ContainerPlat (cplat) on a Windows VM (the "L1") via `c-aci-testing vm runc`. Covers the dual workloads/<name>-cplat-vm/ + workloads/<name>-cplat-vm-nonconf/ bicep layout (NOT real ACI deploys — only LCOW config generation), the .github/workflows/vm-workload-<name>-in-cplat.yml workflow that runs vm_create_traced.sh + `c-aci-testing vm runc` + vm_check_container_output.sh, the confidential/non-confidential split, Premium Azure Files storage discovery via tags.purpose, and the cplatBlobName / vmImage / confidential / vmSize / shareName argument plumbing. Use when the user says "run on ContainerPlat", "in-cplat test", "test on Windows VM via cplat", "stress test v2 in cplat", or wants to compare cplat versions / VM SKUs / official-vs-Atlas images. Covers gotchas: bicep is NEVER deployed as ACI so `listKeys()` / `environment()` MUST NOT be used; `secureValue` is rejected by vm_generate_scripts.py (use plain `value`); cifs `closetimeo=1` requires Linux 5.11+; `confidential` boolean defaults need `inputs.confidential == false && 'false' || 'true'` pattern; vm_simple.yml is the canonical "deploy a cplat VM" reference.
---

# Adding a ContainerPlat-on-VM (cplat-in-VM) workload

This pattern runs a Linux container **inside a confidential UVM hosted by ContainerPlat on a Windows VM**. The Windows VM is the "L1"; the Linux container in the LCOW UVM is the "L2". Used to test ContainerPlat releases, UVM kernels, and host hardware combinations without going through real ACI.

If you want to run a container in real ACI, use [add-aci-test](../add-aci-test/SKILL.md). If you want to run a script directly on a Linux VM (with or without confidential VM hardware), use [add-regular-vm-test](../add-regular-vm-test/SKILL.md).

## Architecture

```
Windows VM (L1, runs cplat)
└─ runhcs-lcow (ContainerPlat)
   └─ LCOW UVM (Linux, optionally SEV-SNP confidential)
      └─ Your container (the workload)
```

The workflow uses `c-aci-testing vm runc <workload-dir>` which:
1. Parses your bicep template as if it were an ACI deployment.
2. Translates the ACI `containerGroups` resource to CRI/LCOW JSONs (`pod.snp.json`, `container.json`, `pull.json`).
3. SCPs them to the Windows VM.
4. Runs `crictl runp` + `crictl run` to start the container in the UVM.

**The bicep is therefore NOT a real ACI deployment** — it's a template that `c-aci-testing vm generate_scripts` consumes. This is the source of most of the gotchas below.

The canonical "deploy a cplat-capable Windows VM" reference is [.github/workflows/vm-simple.yml](../../../.github/workflows/vm-simple.yml) — read it first.

## 1. Two workload dirs: conf and non-conf

A cplat-in-VM test typically has both variants:

- `workloads/<name>-cplat-vm/` — confidential UVM (allow_all CCE policy).
- `workloads/<name>-cplat-vm-nonconf/` — non-confidential UVM (no policy).

The workflow picks between them based on its `confidential` input. Reasons to keep them separate rather than conditional-in-bicep:

- The confidential variant needs `sku: 'Confidential'` + `confidentialComputeProperties: { ccePolicy: ... }`. Non-confidential must NOT have these.
- `c-aci-testing policies gen` only runs against the confidential one.

## 2. `workloads/<name>-cplat-vm/<name>-cplat-vm.bicep`

This template is consumed by `c-aci-testing vm generate_scripts`, not deployed as ARM. **Critical constraints:**

- **No `environment()`** — vm_generate_scripts can't resolve it. Pass the FQDN (e.g. `<account>.file.core.windows.net`) as a plain param instead.
- **No `listKeys()`, no `existing` resource lookups** — they need a real ARM deployment context. Fetch credentials in the workflow (`az storage account keys list`) and pass them in as `@secure() param`s.
- **No `secureValue` env vars** — [vm_generate_scripts.py](https://github.com/microsoft/confidential-aci-testing) reads `env["value"]`, not `env["secureValue"]`. Use plain `{ name: 'key', value: param }`. The `@secure()` annotation on the param itself is still useful for masking in the workflow.

### Template (confidential variant)

```bicep
// IMPORTANT: This template is NOT meant to be deployed as a real ACI container
// group. It is only consumed by `c-aci-testing vm generate_scripts` / `vm runc`
// to produce LCOW configs for ContainerPlat on a Windows VM.

param location string = 'unknown'
param ccePolicies object
param registry string
param repository string
param tag string
param branch string = 'local'

@description('VM SKU label, traced into Kusto for breakdown.')
param vmSku string = ''
@description('ContainerPlat blob name label, traced into Kusto.')
param cplatBlob string = ''

// Storage params (workflow resolves these out-of-band). All plain strings —
// no environment() / listKeys() / existing resources.
param storageAccountName string
@secure()
param storageAccountKey string
param storageAccountFqdn string
param shareName string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.<name_with_underscores>
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers/<image>' : repository}:${empty(tag) ? 'latest' : tag}'
          resources: { requests: { memoryInGB: 16, cpu: 4 } }
          securityContext: { privileged: true }   // needed for cifs mount etc.
          environmentVariables: [
            { name: 'LOCATION', value: location }
            { name: 'PLATFORM', value: 'cplat-vm' }
            { name: 'BRANCH', value: branch }
            { name: 'VM_SKU', value: vmSku }
            { name: 'CPLAT_BLOB', value: cplatBlob }
            { name: 'CONFIDENTIAL', value: 'true' }   // 'false' in nonconf variant
            { name: 'storage_account', value: storageAccountName }
            { name: 'share_name', value: shareName }
            { name: 'storage_key', value: storageAccountKey }  // NOT secureValue
            { name: 'storage_fqdn', value: storageAccountFqdn }
          ]
          command: [
            '/usr/bin/python3'
            '/var/www/<harness>.py'
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
```

Non-conf variant: drop `sku: 'Confidential'`, drop `confidentialComputeProperties`, drop `ccePolicies` param, set `CONFIDENTIAL=false`. Otherwise identical.

Underscore-vs-hyphen gotcha: `ccePolicies` is an object keyed by an identifier. The workload directory may be `workloads/foo-bar-cplat-vm`, but the bicep object key must be `foo_bar_cplat_vm` (underscores). `policies gen` writes the key with underscores.

### `<name>-cplat-vm.bicepparam`

Standard structure; the workflow fills in placeholders via `c-aci-testing aci param_set`:

```bicep
using './<name>-cplat-vm.bicep'

// Image info
param registry=''
param repository=''
param tag='<your tag>'

// Deployment info
param location=''
param ccePolicies={
  <name_with_underscores>: '<base64 of an allow_all rego policy>'  // policies gen overrides this
}
param vmSku=''
param cplatBlob=''
param storageAccountName=''
param storageAccountKey=''
param storageAccountFqdn=''
param shareName=''
```

The base64 in `ccePolicies` is a placeholder; `c-aci-testing policies gen --policy-type allow_all` rewrites it at runtime.

### `docker-compose.yml`

Same as for ACI workloads — needed for `c-aci-testing images pull` (which `vm generate_scripts` doesn't use, but `policies gen` does):

```yaml
version: '3'
services:
  primary:
    image: ${REGISTRY:-cacidashboardaci.azurecr.io}/${REPOSITORY:-prebuilt-test-containers/<image>}:${TAG:-latest}
```

## 3. Harness script

Same conventions as the regular-VM skill: emit `OUTPUT: {json}` lines at the END so they survive `az vm run-command invoke` truncation (the workflow uses `vm_check_container_output.sh` which is also bounded). Print env info early so [scripts/parse_container_output.py](../../../scripts/parse_container_output.py) can extract uname / cpu model / etc.

Unlike the regular-VM skill, you typically **don't need a wait loop** for cplat-in-VM — `c-aci-testing vm runc` blocks until the container exits, so by the time the `Container output` step runs, the harness has finished. The `ALL-DONE` marker line is still a useful sanity-check (lets a human reading the log see the harness reached the end) but isn't polled by anything; `parse_container_output.py` ignores it.

### Azure Files in the UVM — cifs option gotcha

If you mount an SMB share from inside the UVM, **`closetimeo=1` was added to cifs.ko in Linux 5.11**. Older UVMs (e.g. ContainerPlat 0.128.x has a 5.10 kernel) reject it with `EINVAL`. Detect and conditionally include it:

```python
kernel_release = os.uname().release
major_minor = tuple(int(x) for x in re.match(r"(\d+)\.(\d+)", kernel_release).groups())
has_closetimeo = major_minor > (5, 10)
mount_opts = "vers=3.1.1,...,actimeo=30" + (",closetimeo=1" if has_closetimeo else "")
```

The harness should be baked into the container image (in [containers/stress-tests-server-ubuntu.Dockerfile](../../../containers/stress-tests-server-ubuntu.Dockerfile) etc.) so it's present at `/var/www/<harness>.py`. Don't SAS-fetch into the UVM — the container's network may not be set up the way you expect.

## 4. `.github/workflows/vm-workload-<name>-in-cplat.yml`

Copy from an existing cplat-in-VM workflow (e.g. [vm-simple.yml](../../../.github/workflows/vm-simple.yml) for the bare cplat-VM setup) and add the workload-specific bits.

### Inputs

Make these the standard cplat-in-VM knobs (all the existing tests use these):

```yaml
workflow_dispatch:
  inputs:
    id: { type: string }
    location: { type: string, default: westeurope }
    vmImage:
      type: string
      description: VM image ID (Atlas) or the literal string "official" for marketplace images
      default: official
    cplatBlobName:
      type: string
      description: ContainerPlat blob name; defaults to vars.CPLAT_NEXT_6_1_BLOB_NAME
      default: ''
    confidential: { type: boolean, default: true }
    vmSize: { type: string, default: Standard_DC8as_cc_v5 }
    cleanup: { type: boolean, default: true }
workflow_call:
  inputs: { ...same... }
```

Mirror these on `workflow_call` so [perf-region.yml](../../../.github/workflows/perf-region.yml) etc. can call them.

### Env block — the conf/nonconf split

```yaml
env:
  KUSTO_CONNECTION_STRING: ${{ secrets.KUSTO_CONNECTION_STRING }}
  KUSTO_DATABASE: ${{ secrets.KUSTO_DATABASE }}
  KUSTO_TABLE: CACITestStepTrace
  TEST_TYPE: vm
  TEST_NAME: <name> ContainerPlat VM
  RUN_LINK: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
  DEPLOYMENT_NAME: ${{ inputs.id || '<short>' }}-${{ inputs.location || 'westeurope' }}-${{ github.run_number }}
  SUBSCRIPTION: ${{ vars.SUBSCRIPTION_ACI }}
  RESOURCE_GROUP: c-aci-dashboard
  REGISTRY: cacidashboardaci.azurecr.io
  REPOSITORY: prebuilt-test-containers/<image>
  TAG: <your tag>
  STORAGE_ACCOUNT: cacitestingstorageaci
  LOCATION: ${{ inputs.location || 'westeurope' }}
  MANAGED_IDENTITY: cacidashboard-${{ inputs.location || 'westeurope' }}
  CLEANUP: ${{ inputs.cleanup }}
  VM_SIZE: ${{ inputs.vmSize || 'Standard_DC8as_cc_v5' }}
  VM_IMAGE: ${{ inputs.vmImage != 'official' && inputs.vmImage || '' }}
  USE_OFFICIAL_IMAGES: ${{ (inputs.vmImage == '' || inputs.vmImage == 'official') && 'true' || '' }}
  CPLAT_BLOB_NAME: ${{ inputs.cplatBlobName || vars.CPLAT_NEXT_6_1_BLOB_NAME }}
  WIN_FLAVOR: 'ws2025'
  VM_ZONE: ''
  # confidential defaults to true: if explicitly false → 'false'; otherwise 'true'.
  CONFIDENTIAL: ${{ inputs.confidential == false && 'false' || 'true' }}
  WORKLOAD_DIR: ${{ inputs.confidential == false && 'workloads/<name>-cplat-vm-nonconf' || 'workloads/<name>-cplat-vm' }}
  WORKLOAD_PREFIX: ${{ inputs.confidential == false && 'lcow_<name>-cplat-vm-nonconf' || 'lcow_<name>-cplat-vm' }}
  STORAGE_TAG_PURPOSE: ${{ inputs.confidential == false && 'caci-nonconf-testing-storage-premium' || 'caci-testing-storage-premium' }}
```

Why `inputs.confidential == false && 'false' || 'true'` instead of the more obvious `inputs.confidential && 'true' || 'false'`: the first form treats "input undefined" as true (matches the input default). The second form makes undefined become `'false'`, breaking push/PR/scheduled runs.

### Steps

```yaml
- name: Checkout
  uses: actions/checkout@v4

- name: Downgrade Azure CLI    # vm_create_traced.sh needs older cli
  env:
    AZ_CLI_VERSION: "2.81.0"
  run: ./scripts/install-az-cli.sh

- name: Log into Azure
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID_ACI }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.SUBSCRIPTION_ACI }}

- name: Initialize Run
  env: { GH_TOKEN: ${{ github.token }} }
  run: ./scripts/init_run.sh

# Optional: resolve a per-region Premium FileStorage account by tag,
# fetch its key + FQDN, create a per-run share. Skip if your test
# doesn't need a share.
- name: Resolve storage account
  id: storage
  run: |
    ./scripts/tracing/trace_step.py --start 'Resolve storage account'
    ACCOUNT=$(az storage account list \
      --query "[?location=='$LOCATION' && tags.purpose=='$STORAGE_TAG_PURPOSE'].name | [0]" \
      -o tsv)
    [ -z "$ACCOUNT" ] && { ./scripts/tracing/trace_step.py --complete --strict --err "No $STORAGE_TAG_PURPOSE in $LOCATION"; exit 1; }
    KEY=$(az storage account keys list --account-name "$ACCOUNT" --resource-group $RESOURCE_GROUP --query '[0].value' -o tsv)
    echo "::add-mask::$KEY"
    SUFFIX=$(az cloud show --query "suffixes.storageEndpoint" -o tsv)
    SHARE="<short>-${{ github.run_number }}-${{ github.run_attempt }}"
    echo "account=$ACCOUNT"   >> "$GITHUB_OUTPUT"
    echo "key=$KEY"           >> "$GITHUB_OUTPUT"
    echo "fqdn=${ACCOUNT}.file.${SUFFIX}" >> "$GITHUB_OUTPUT"
    echo "share=$SHARE"       >> "$GITHUB_OUTPUT"
    ./scripts/tracing/trace_step.py --complete --strict

- name: Create Azure Files share
  run: |
    az storage share-rm create --storage-account ${{ steps.storage.outputs.account }} \
      --resource-group $RESOURCE_GROUP --name ${{ steps.storage.outputs.share }} \
      --quota 51200 --enabled-protocols SMB

- name: Set bicep parameters
  run: |
    c-aci-testing aci param_set $WORKLOAD_DIR --parameter vmSku="$VM_SIZE"
    c-aci-testing aci param_set $WORKLOAD_DIR --parameter cplatBlob="$CPLAT_BLOB_NAME"
    c-aci-testing aci param_set $WORKLOAD_DIR --parameter branch=${GITHUB_REF_NAME}
    c-aci-testing aci param_set $WORKLOAD_DIR --parameter storageAccountName=${{ steps.storage.outputs.account }}
    c-aci-testing aci param_set $WORKLOAD_DIR --parameter storageAccountKey='${{ steps.storage.outputs.key }}'
    c-aci-testing aci param_set $WORKLOAD_DIR --parameter storageAccountFqdn=${{ steps.storage.outputs.fqdn }}
    c-aci-testing aci param_set $WORKLOAD_DIR --parameter shareName=${{ steps.storage.outputs.share }}

- name: Generate Security Policy
  if: ${{ inputs.confidential }}
  run: |
    c-aci-testing policies gen $WORKLOAD_DIR --deployment-name $DEPLOYMENT_NAME --policy-type allow_all

- name: Deploy VM
  run: ./scripts/vm_create_traced.sh   # traces vm create + reads env

- name: Run container on VM
  run: |
    ./scripts/tracing/trace_step.py --start 'vm runc'
    c-aci-testing vm runc $WORKLOAD_DIR --deployment-name $DEPLOYMENT_NAME --prefix $WORKLOAD_PREFIX

- name: Print VM info
  if: always()
  continue-on-error: true
  run: scripts/vm_print_info.sh

- name: Report result
  if: always()
  run: ./scripts/trace_run_result.sh ${{ job.status }}

- name: Check dmesg
  if: always()
  continue-on-error: true
  run: |
    ./scripts/tracing/trace_step.py --start 'Check dmesg'
    c-aci-testing vm exec --deployment-name $DEPLOYMENT_NAME 'Get-Item C:\*\dmesg*.log | foreach { echo ""; echo ""; echo $_.FullName; cat -Raw $_ } > C:\all-dmesg.log'
    c-aci-testing vm cat --deployment-name $DEPLOYMENT_NAME 'C:\all-dmesg.log' > dmesg.log
    cat dmesg.log
    ./scripts/_check_dmesg.sh "dmesg.log"

- name: Container output
  if: always()
  run: ./scripts/vm_check_container_output.sh   # tails container_*.log + parses OUTPUT:

- name: Report result (post-parse)
  if: always()
  run: ./scripts/trace_run_result.sh ${{ job.status }}

- name: Remove VM
  if: always()
  run: |
    if [ "$CLEANUP" != false ]; then
      c-aci-testing vm remove --deployment-name $DEPLOYMENT_NAME || true
      az vm delete --resource-group $RESOURCE_GROUP --name ${DEPLOYMENT_NAME}-vm --yes --force-deletion yes --verbose || true
    fi

- name: Delete Azure Files share
  if: always()
  continue-on-error: true
  run: |
    if [ "$CLEANUP" != false ] && [ -n "${{ steps.storage.outputs.share }}" ]; then
      az storage share-rm delete --storage-account ${{ steps.storage.outputs.account }} \
        --resource-group $RESOURCE_GROUP --name ${{ steps.storage.outputs.share }} --yes || true
    fi
```

## 5. Wire into [perf-region.yml](../../../.github/workflows/perf-region.yml)

cplat-in-VM tests are expensive and contend on VM quota. Chain them with `needs:` rather than running in parallel:

```yaml
my-cplat-stage:
  if: ${{ !cancelled() }}
  needs: <previous-stage>   # serialize against other VM stages
  secrets: inherit
  uses: ./.github/workflows/vm-workload-<name>-in-cplat.yml
  with:
    id: <unique>
    location: ${{ inputs.location }}
    vmImage: official
    cplatBlobName: cplat-0.129.1
    confidential: false
    vmSize: Standard_D8s_v6
```

## 6. Kusto labelling

Add the new `TEST_NAME` to the base query. Rows from this test have `TestType=vm` but you want them distinguished from regular-VM rows; use `TestName`:

```kql
| extend env=case(
    TestName == '<your TEST_NAME>', 'cplat-vm',
    TestType == 'aci', 'c-aci',
    TestType == 'aci-non-confidential', 'aci',
    TestType == 'vm', 'vm',
    '???')
| extend env_label = case(
    env == 'cplat-vm', strcat('cplat-vm-', vm_family, '-', iff(confidential == 'true', 'conf', 'nonconf'), '-', cplat_short),
    env == 'vm' and isnotempty(vm_sku), strcat('vm-', vm_sku),
    env)
```

The harness should emit `vm_sku`, `cplat_blob`, and `confidential` in its metadata OUTPUT so this query works.

## Gotchas (read these)

- **NEVER `secureValue` in cplat-vm bicep**: vm_generate_scripts.py reads `env["value"]`; secureValue triggers `KeyError`. Keep `@secure()` on the param for workflow masking, but pass it as `value:` in the container's env array.
- **NEVER `environment()` / `listKeys()` / `existing` in cplat-vm bicep**: not deployed as ARM; pass everything as plain params from the workflow.
- **Confidential boolean default**: use `inputs.confidential == false && 'false' || 'true'`, NOT `inputs.confidential && 'true' || 'false'`. The latter breaks default-true semantics on push/PR/scheduled runs.
- **cifs `closetimeo=1` requires kernel ≥ 5.11**: older cplat UVMs (5.10) reject the whole mount with `mount error(22): Invalid argument`. Detect and omit.
- **mount EINVAL ≠ no CIFS support**: missing cifs.ko gives `mount: unknown filesystem type 'cifs'` (ENODEV); EINVAL means the kernel accepted the call and rejected an option.
- **Underscore vs hyphen**: dir is `workloads/foo-bar-cplat-vm/foo-bar-cplat-vm.bicep`, but the `ccePolicies` object key inside it must be `foo_bar_cplat_vm`. `policies gen` writes underscores.
- **`vmImage: official` vs Atlas ID**: the workflow treats the literal string `'official'` (and empty string) as "use Azure Marketplace ws2025 image". Anything else is an Atlas blob ID. The `USE_OFFICIAL_IMAGES` / `VM_IMAGE` env split derives from this.
- **TAG bump on harness changes**: the harness is baked into the container image. If you change `stress_test_v2.py` etc., rebuild the prebuilt image and bump `TAG:` in the workflow, otherwise the cplat UVM runs the old harness.
- **CPLAT_NEXT_6_1_BLOB_NAME vs CPLAT_CURR_BLOB_NAME**: `vars.CPLAT_*_BLOB_NAME` are repo-level GitHub Actions variables pointing to the canonical cplat releases. Use as default and let workflow_dispatch override.
- **WIN_FLAVOR=ws2025**: ws2022 also exists; some cplat blobs only work on one. ws2025 is the current default.
- **Don't add zone unless required**: zone-aware perf comparisons are rare; leaving `VM_ZONE: ''` lets Azure pick.
- **`vm_create_traced.sh` reads from env**: it expects `VM_SIZE`, `VM_IMAGE`, `USE_OFFICIAL_IMAGES`, `CPLAT_BLOB_NAME`, `WIN_FLAVOR`, `VM_ZONE`, `DEPLOYMENT_NAME`, `LOCATION`, `MANAGED_IDENTITY` to be set in `env:`. Don't pass them as args.
- **Output truncation**: `vm_check_container_output.sh` fetches `C:\container_*.log` via `c-aci-testing vm cat`; that has a size cap. Same advice as the VM skill: emit final `OUTPUT:` lines at the very end of the harness.
