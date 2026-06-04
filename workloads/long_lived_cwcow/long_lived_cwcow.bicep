// Confidential WCOW long-running workload.
// Mirrors workloads/long_lived but with osType: 'Windows'. Boots a confidential
// Windows UVM and keeps a single nanoserver container alive forever via
// `ping -t 127.0.0.1 > nul` (the canonical Windows "keep me running" pattern,
// no extra package required, no PowerShell needed). Suitable as a long-uptime
// stability baseline once a confidential WCOW region opens, and today on a
// dev host with the confidential cri-containerd cplat.
//
// Unlike workloads/long_lived this workload does NOT pull from a private ACR
// (so it works without imageRegistryCredentials and managed identity).
// `restartPolicy: 'OnFailure'` so a hard container crash auto-restarts and
// surfaces in the harness's check.ps1.
//
// Note: digest inlined per minimal_cwcow.bicep rationale.
param location string
param tag string
param ccePolicies object

param cpu int = 1
param memoryInGb int = 2

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Windows'
    sku: 'Confidential'
    restartPolicy: 'OnFailure'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.long_lived_cwcow
    }
    containers: [
      {
        name: 'primary'
        properties: {
          // Digest-pinned by default; pass a non-empty `tag` to opt into tag
          // resolution. See minimal_cwcow.bicep for why a tag ref breaks the
          // c-aci-testing VM harness's manifest resolution for Windows images.
          image: empty(tag) ? 'mcr.microsoft.com/windows/nanoserver@sha256:4d60fd27581d94a2866c7b54b3ade605de37a74e11aa8314a963fb3272a67667' : 'mcr.microsoft.com/windows/nanoserver:${tag}'
          command: [
            'cmd.exe'
            '/c'
            'ping -t 127.0.0.1 > nul'
          ]
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
