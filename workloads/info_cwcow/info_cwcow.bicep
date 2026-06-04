// Confidential WCOW info-dump workload.
// Mirrors workloads/info but with osType: 'Windows' and a Windows nanoserver
// image. Runs a small one-shot info dump (Windows version, hostname, OS
// build) and exits — the smallest signal beyond "container starts" that the
// confidential WCOW guest is reachable and reading the Windows kernel.
//
// No external image dependencies: uses cmd.exe builtins (ver, hostname, reg)
// so the workload runs on any host with cri-containerd-confidential cplat
// without needing the dashboard's ACR.
param location string
param tag string
param ccePolicies object

param cpu int = 2
param memoryInGb int = 4

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Windows'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.info_cwcow
    }
    containers: [
      {
        name: 'primary'
        properties: {
          // Pin by digest by default: the c-aci-testing VM harness resolves
          // tag refs via `oras manifest fetch --platform linux/amd64`
          // (utils/vm.py:resolve_manifest_hash), which has no match in the
          // Windows nanoserver manifest list and fails — a digest ref skips
          // that resolution. Pass a non-empty `tag` to opt into tag resolution.
          image: empty(tag) ? 'mcr.microsoft.com/windows/nanoserver@sha256:4d60fd27581d94a2866c7b54b3ade605de37a74e11aa8314a963fb3272a67667' : 'mcr.microsoft.com/windows/nanoserver:${tag}'
          command: [
            'cmd.exe'
            '/c'
            'echo ===HOSTNAME=== & hostname & echo ===VERSION=== & ver & echo ===ARCH=== & echo %PROCESSOR_ARCHITECTURE% & echo ===ENV=== & set & echo ===EOF==='
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
