// Confidential WCOW baseline workload — Server Core variant.
// Identical in intent to workloads/minimal_cwcow but uses the larger
// Server Core image (mcr.microsoft.com/windows/servercore:ltsc2025)
// instead of nanoserver. Server Core exercises a meaningfully larger
// guest surface than nanoserver:
//   - more drivers preloaded in the UVM
//   - bigger registry hive (servercore has WMI, schtasks, full reg DB, etc.)
//   - powershell.exe present (nanoserver only has cmd.exe)
//   - net.exe, sc.exe, perfmon counters, ...
// so it catches confidential-UVM regressions that nanoserver wouldn't.
//
// This is the image used by the SF onebox C-WCOW end-to-end test that we
// proved working through the full RP -> AM -> CAS -> IM -> Atlas path
// last week, so this workload now mirrors that path at the standalone VM
// level too.
//
// Note: the servercore digest is inlined as a string literal rather than
// via a `var`, matching minimal_cwcow.bicep. See its inline comment for the
// parse_bicep `variables()` rationale.
param location string
param tag string
param ccePolicies object

param cpu int = 4
param memoryInGb int = 8

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Windows'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.minimal_cwcow_servercore
    }
    containers: [
      {
        name: 'primary'
        properties: {
          // Digest-pinned by default; pass a non-empty `tag` to opt into tag
          // resolution. See minimal_cwcow.bicep for why a tag ref breaks the
          // c-aci-testing VM harness's manifest resolution for Windows images.
          image: empty(tag) ? 'mcr.microsoft.com/windows/servercore@sha256:4566c6115c63ea3a3f15fd368d78dbf7a08064bb94d56428fab00eec033aea67' : 'mcr.microsoft.com/windows/servercore:${tag}'
          command: [
            'cmd.exe'
            '/c'
            'echo hello c-wcow servercore && ver && hostname && ping -n 5 localhost'
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
