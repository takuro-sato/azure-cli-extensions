---
name: add-regular-vm-test
description: Step-by-step guide for adding a workload that runs directly on a Linux VM (regular Ubuntu or SEV-SNP confidential VM, NOT via ContainerPlat). Covers the workloads/<name>/vm.bicep template, the .github/workflows/workload-<name>.yml workflow that uploads the harness to blob storage with a SAS URL, deploys the VM via `az deployment group create`, polls /tmp/<name>.log via `az vm run-command invoke`, parses `OUTPUT:` lines via scripts/parse_container_output.py, and tears down the VM + any per-run storage shares. Use when the user says "add a VM test", "regular VM benchmark", "non-cplat VM test", or wants to run a script directly on Ubuntu (with or without confidential-VM security profile). Covers gotchas: harness must reach the VM somehow (SAS blob); `az vm run-command invoke` truncates long output; `OUTPUT:` lines should be emitted at the END of the harness; CVM image SKU is `cvm` not `server`; `securityEncryptionType: 'DiskWithVMGuestState'` is required on CVM osDisk.
---

# Adding a regular-VM (or confidential-VM) workload

A "regular VM" workload here means: a Linux VM (Ubuntu) where your test script runs **directly on the VM OS**, not inside ContainerPlat. This covers two cases that share ~95 % of the code:

1. **Regular VM** — vanilla Ubuntu, `Standard_D*as_v*` SKU.
2. **Confidential VM (CVM)** — SEV-SNP confidential VM, `Standard_DC*as_v*` SKU (note: `DC*as_v*`, NOT `DC*as_cc_v*`; the `_cc_` suffix is for confidential-child via ContainerPlat).

If you want to run a container inside ContainerPlat on a Windows VM instead, see [add-cplat-in-vm-test](../add-cplat-in-vm-test/SKILL.md).

## When to use which

| What you want                                    | Use                                  |
| ------------------------------------------------ | ------------------------------------ |
| Benchmark Ubuntu kernel / userspace directly     | This skill (regular VM)              |
| Compare confidential-VM vs regular-VM perf       | This skill (CVM + regular VM)        |
| Run a container inside SEV-SNP UVM via cplat     | [add-cplat-in-vm-test](../add-cplat-in-vm-test/SKILL.md) |
| Run a container in real ACI                      | [add-aci-test](../add-aci-test/SKILL.md)                 |

## 1. Harness script

Place the harness under [containers/stress_test_workloads/](../../../containers/stress_test_workloads/) (or a similar shared scripts dir). Conventions:

- Emit `OUTPUT: {...json...}` lines that get auto-ingested into Kusto by [scripts/parse_container_output.py](../../../scripts/parse_container_output.py).
- Emit those OUTPUT lines **at the very end** of the script, after all heavy work. `az vm run-command invoke` truncates long output, so an OUTPUT line printed early can be dropped if fio/sysbench/etc. dumps a lot of text after it.
- Print env info early so [scripts/parse_container_output.py](../../../scripts/parse_container_output.py) can extract it: `uname -a`, `cat /proc/cpuinfo` (it auto-extracts `model name:`), `lscpu`, `df -h .`, etc.
- Emit a final `ALL-DONE` marker line. **This is purely a workflow-side convention**: `parse_container_output.py` doesn't care about it. The workflow's wait loop greps the VM log for `ALL-DONE` to know when the harness has finished, then fetches the full log and runs the parser. Without it, the workflow has no signal that the run completed and will time out.
- Optionally read metadata env vars and include them in the metadata OUTPUT: `LOCATION`, `PLATFORM`, `VM_SKU`, `BRANCH`, `CONFIDENTIAL`. These let the Kusto query distinguish rows.

Don't bake the harness into the VM image — fetch it at runtime via SAS URL (next step). This avoids needing a custom image rebuild when you tweak the script.

## 2. `workloads/<name>/vm.bicep`

Copy from an existing example and adapt:

- Regular VM: copy [workloads/stress-test-v2-vm/vm.bicep](../../../workloads/stress-test-v2-vm/vm.bicep) (if present on your branch) or [workloads/perf-regular-vm/vm.bicep](../../../workloads/perf-regular-vm/vm.bicep).
- CVM: copy [workloads/stress-test-v2-cvm/vm.bicep](../../../workloads/stress-test-v2-cvm/vm.bicep) or [workloads/perf-cvm/vm.bicep](../../../workloads/perf-cvm/vm.bicep).

Required params (keep these names — the workflow passes them by name):

```bicep
param deploymentName string
param location string = resourceGroup().location
param vmSize string = 'Standard_D4as_v6'   // or Standard_DC4as_v6 for CVM
param adminUsername string = 'azureuser'
@secure()
param adminPassword string
@secure()
param harnessUrl string                    // SAS URL to fetch the harness
param branch string = 'local'
// Add any other per-test params (e.g. shareName, storage params)
```

### Networking + base resources

Standard pattern (same for both): public IP + VNet + NIC + VM. Don't set zones unless required; perf comparisons are usually zone-agnostic. Use `enableAcceleratedNetworking: true` on the NIC.

### Image reference

Regular VM:
```bicep
imageReference: {
  publisher: 'canonical'
  offer: 'ubuntu-24_04-lts'
  sku: 'server'
  version: 'latest'
}
```

Confidential VM (note the `cvm` SKU and required `securityProfile` blocks):
```bicep
securityProfile: {
  securityType: 'ConfidentialVM'
  uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
}
storageProfile: {
  osDisk: {
    createOption: 'FromImage'
    diskSizeGB: 128
    managedDisk: {
      storageAccountType: 'Premium_LRS'
      securityProfile: { securityEncryptionType: 'DiskWithVMGuestState' }
    }
    deleteOption: 'Delete'
  }
  imageReference: {
    publisher: 'Canonical'
    offer: 'ubuntu-24_04-lts'
    sku: 'cvm'
    version: 'latest'
  }
}
```

Note: the `server` (non-CVM) image will also boot on a `DC*as_v*` SKU and the guest will still be an SEV-SNP VM thanks to the Hyper-V Compatibility Layer (HCL) — it is the `securityType: 'ConfidentialVM'` on the VM resource, not the image, that decides whether the guest gets an SNP VM. The `cvm` image is preferred because:

- It supports `securityEncryptionType: 'DiskWithVMGuestState'` (OS disk + VMGS encrypted with a VMGS-derived key). The `server` image is incompatible with this `securityEncryptionType` and the deployment fails; you'd have to drop the `managedDisk.securityProfile` block (or use `NonPersistedTPM` if available) which means no encrypted OS disk.
- It ships preinstalled with the SNP guest attestation kmods / userspace bits (e.g. `/dev/sev-guest`, tdx-tools-equivalents). On `server` you'd install these manually.
- It is set up for Gen2 / UEFI / secure-boot / vTPM out of the box.

So: if you actually want a CVM with disk encryption and ready-to-use attestation tooling, use `cvm`. If you specifically want to test the HCL path (a regular Ubuntu image running on SNP hardware), use `server` and drop the `managedDisk.securityProfile`. Don't mix `securityEncryptionType: 'DiskWithVMGuestState'` with `sku: 'server'` — the deployment will fail.

### Optional: Premium Azure Files

If the harness benchmarks/uses an SMB share, look up a pre-provisioned Premium FileStorage account (created in [azure/regional-shared.bicep](../../../azure/regional-shared.bicep)) by `uniqueString(...)` name. **Do not pre-create the share in the bicep file** — quotas are expensive (50 TiB). Have the workflow create the share per-run and pass its name in as a param. See [add-cplat-in-vm-test](../add-cplat-in-vm-test/SKILL.md) for the storage discovery + share-lifecycle pattern; it applies identically here.

### `runCommands` resource — running the harness

```bicep
resource runCommand 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  name: 'runCommand'
  location: location
  parent: virtualMachine
  properties: {
    source: {
      script: join([
        '#!/bin/bash'
        'exec >> /tmp/<name>.log 2>&1'  // workflow tails this file
        'set -ex'
        'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 fio sysbench cifs-utils curl 2>/dev/null'
        'mkdir -p /var/www && cd /var/www'
        'curl -sSfL -o harness.py "${harnessUrl}"'
        'chmod +x harness.py'
        'export LOCATION="${location}"'
        'export VM_SKU="${vmSize}"'
        'export PLATFORM=regular-vm'   // or 'regular-cvm' for CVM
        'export CONFIDENTIAL=true'     // CVM only
        'export BRANCH="${branch}"'
        'python3 ./harness.py'
      ], '\n')
    }
  }
}
```

Each list element becomes one shell line. Use `'export FOO="${bar}"'` (Bicep interpolation outside the quotes, shell variable expansion inside).

Also create a minimal `<name>.bicepparam` next to the bicep so `az deployment group create --template-file vm.bicep` doesn't complain (only needed if you also want to deploy via `c-aci-testing`).

## 3. `.github/workflows/workload-<name>.yml`

Copy from [workload-perf-regular-vm.yml](../../../.github/workflows/workload-perf-regular-vm.yml) or the corresponding stress-test-v2 workflow. Required pieces:

### Env

```yaml
env:
  KUSTO_CONNECTION_STRING: ${{ secrets.KUSTO_CONNECTION_STRING }}
  KUSTO_DATABASE: ${{ secrets.KUSTO_DATABASE }}
  KUSTO_TABLE: CACITestStepTrace
  TEST_TYPE: vm
  TEST_NAME: <human-readable name>   # Used to filter rows in Kusto
  RUN_LINK: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
  DEPLOYMENT_NAME: ${{ inputs.id || '<short>' }}-${{ inputs.location || 'westeurope' }}-${{ github.run_number }}
  SUBSCRIPTION: ${{ vars.SUBSCRIPTION_ACI }}
  RESOURCE_GROUP: c-aci-dashboard
  LOCATION: ${{ inputs.location || 'westeurope' }}
  CLEANUP: ${{ inputs.cleanup }}
  VM_SIZE: ${{ inputs.vmSize || 'Standard_D4as_v6' }}
```

Give CVM a different `TEST_NAME` (e.g. `stress test v2 confidential VM` vs `stress test v2 regular VM`) so dashboard queries can distinguish them. The harness should also set `CONFIDENTIAL=true` for CVM so Kusto rows are tagged.

### Steps

1. **Checkout / Azure login / `init_run.sh`** — boilerplate, copy verbatim.
2. **Upload harness to blob + generate SAS** — `az storage container create` (idempotent) → `az storage blob upload` → `az storage blob generate-sas --permissions r --expiry 4h`. Mask the URL with `echo "::add-mask::$HARNESS_URL"`. Use a unique blob name per run: `<harness>-${{ github.run_id }}-${{ github.run_attempt }}.py`.
3. **Deploy VM** — `az deployment group create --template-file workloads/<name>/vm.bicep --parameters location=$LOCATION deploymentName=$DEPLOYMENT_NAME adminPassword=<random> vmSize=$VM_SIZE harnessUrl=...` — use a random password: `PASSWORD=$(head --bytes 8 /dev/urandom | base64)`.
4. **Wait for ALL-DONE** — loop calling `az vm run-command invoke ... --scripts "cat /tmp/<name>.log"`, grep for `ALL-DONE`. Cap iterations (e.g. 20 × 30 s = 10 min).
5. **Fetch full VM log** + `scripts/parse_container_output.py --must-have-output --error-count-threshold 100000 vm-output.log` — auto-traces all `OUTPUT:` JSON to Kusto.
6. **Report result** — `./scripts/trace_run_result.sh ${{ job.status }}`.
7. **Cleanup** — `if [ "$CLEANUP" != false ]`: `az vm delete --yes --force-deletion yes`, then `az network nic/public-ip/vnet delete` (NIC first; the others depend on it being gone).
8. **Cleanup any per-run shares** (if applicable) — `az storage share-rm delete`.

### Wait-loop template

```yaml
- name: Wait for ALL-DONE
  run: |
    ./scripts/tracing/trace_step.py --start 'Wait for ALL-DONE'
    for i in $(seq 1 20); do
      OUTPUT=$(az vm run-command invoke \
        --resource-group $RESOURCE_GROUP \
        --name ${DEPLOYMENT_NAME}-vm \
        --command-id RunShellScript \
        --scripts "cat /tmp/<name>.log 2>/dev/null || echo 'Log not ready'" \
        --query 'value[0].message' -o tsv 2>/dev/null || echo "")
      echo "$OUTPUT" | tail -20
      if echo "$OUTPUT" | grep -q "ALL-DONE"; then
        ./scripts/tracing/trace_step.py --complete --strict
        break
      fi
      [ $i -eq 20 ] && { ./scripts/tracing/trace_step.py --complete --strict --err "Timeout"; exit 1; }
      sleep 30
    done
```

## 4. Wire into region workflows

If the test should run as part of a per-region rollup, add an entry in [.github/workflows/perf-region.yml](../../../.github/workflows/perf-region.yml) (or the equivalent region.yml for your test category). To avoid quota contention chain VM stages with `needs:` rather than running them in parallel:

```yaml
my-vm-stage:
  if: ${{ !cancelled() }}
  needs: <previous-stage>
  secrets: inherit
  uses: ./.github/workflows/workload-<name>.yml
  with:
    id: <unique-per-run>
    location: ${{ inputs.location }}
    vmSize: Standard_D4as_v6
```

## 5. Kusto labelling

Add the new `TEST_NAME` to the base query that drives your dashboard tiles (e.g. `stress_test_v2_bench`). For CVM, the row has `TestType=vm` and the harness emits `confidential=true`, so a typical mapping is:

```kql
| extend env=case(
    TestName == '<your CVM TestName>', 'cvm',
    TestType == 'vm', 'vm',
    ...)
```

## Gotchas (read these)

- **CVM image SKU**: `sku: 'cvm'` (with `securityEncryptionType: 'DiskWithVMGuestState'`) is what you usually want on confidential SKUs. `sku: 'server'` does still produce a real SEV-SNP VM (HCL boots it that way as long as `securityType: 'ConfidentialVM'` is set on the VM resource), but it's incompatible with `DiskWithVMGuestState` and ships no attestation tooling; you'd have to drop the disk `securityProfile` and install the guest bits yourself.
- **`_cc_v*` vs `_v*`**: `Standard_DC*as_cc_v*` is for confidential-child (ContainerPlat-on-VM). `Standard_DC*as_v*` is a real SEV-SNP confidential VM. They're different things.
- **`az vm run-command invoke` truncates output**: emit important `OUTPUT:` lines at the END of the harness, after all heavy work / large dumps.
- **SAS URL masking**: always `echo "::add-mask::$HARNESS_URL"` before writing to `$GITHUB_OUTPUT`, otherwise it'll appear in step logs.
- **NIC delete order**: VM → NIC → public-IP → VNet. Deleting VNet before NIC fails because the NIC is still attached. Use `|| true` on each because `if: always()` cleanup can race.
- **Random password**: `head --bytes 8 /dev/urandom | base64`. Azure rejects passwords that are too simple even on confidential VMs.
- **No `OUTPUT:` line found**: `parse_container_output.py --must-have-output` will fail-trace the step. Often this means `ALL-DONE` was matched but the harness exited before printing OUTPUT. Always print OUTPUT before ALL-DONE.
- **`ALL-DONE` is a workflow convention, not a parser feature**: the wait-loop step (above) needs to grep for it explicitly; `parse_container_output.py` ignores it. If you skip the wait loop, the parser will happily process a partial mid-run log and emit incomplete OUTPUT to Kusto.
- **Existing storage account lookup**: if you need Azure Files, use `uniqueString(subscription().id, resourceGroup().name, location, 'caci-vm-testing-storage-premium')` to look up the per-region Premium account. Don't create new accounts per test — they take ~5 min to provision.
