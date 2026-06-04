# minimal_cwcow

First **Confidential WCOW** (Windows containers on SNP-protected UVMs)
baseline workload in this repo. Mirrors `workloads/minimal` but with
`osType: 'Windows'` and a Windows nanoserver image pinned by digest.

## What this workload does

- One container group, one container
- Image: `mcr.microsoft.com/windows/nanoserver` (pinned by digest)
- Command: `cmd.exe /c "echo hello c-wcow && ping -n 5 localhost"` —
  prints, pings localhost briefly, exits with status 0
- Resources: 4 CPU, 8 GB RAM (typical WCOW UVM sizing)
- Restart policy: `Never` (one-shot)

## What this workload exists to verify

The smallest possible signal that confidential WCOW container start
works end-to-end on a given host / region. No volumes, no public IP,
no managed identity, no secrets — just "does a confidential Windows
container come up and run".

## How it runs today (no public C-WCOW region yet)

There is no public Azure region accepting confidential WCOW
(`nanoserver:ltsc2025`) deploys at the time this workload was authored.
Until a region opens, the workload is exercised against a Windows host
with the confidential cri-containerd cplat installed (the same host used
to generate CCE policies via `az confcom acipolicygen`).

Pipeline against a dev host:

```powershell
$absTarget = (Resolve-Path workloads\minimal_cwcow).Path
c-aci-testing vm generate_scripts $absTarget $env:TEMP\configs `
    --win-flavor ws2025 --prefix minimal_cwcow

# Copy the generated configs to the host, then:
azcrictl pull --pod-config pull.json mcr.microsoft.com/windows/nanoserver:ltsc2025
azcrictl runp --runtime runhcs-wcow-hypervisor pod_minimal_cwcow.json
azcrictl create --no-pull <podId> container_minimal_cwcow_primary.json pod_minimal_cwcow.json
azcrictl start <containerId>
```

Once a confidential WCOW region is GA the same bicep deploys unchanged
to ACI via `c-aci-testing aci deploy`.

## Notes about the bicep

- The nanoserver image is referenced by digest as a string literal
  rather than via a `var`. Bicep usually inlines `var` references at
  build time, but emits `[variables('name')]` when they appear inside
  another ARM expression (e.g. `if(empty(tag), digest, digest)`). The
  upstream `c-aci-testing parse_bicep` now resolves `variables()`, but
  inlining keeps the workload working against any version.
- `cpu` and `memoryInGb` default to 4 / 8. Lowering them risks failed
  UVM boots; raising them costs more.
- `ccePolicies.minimal_cwcow` is pre-populated in the `.bicepparam`
  with a permissive policy that loads the
  `aci-cc-infra-fragment`. Regenerate with
  `c-aci-testing policies gen workloads/minimal_cwcow --deployment-name <name>`
  if you need a strict policy bound to the actual container layers.
