// Confidential WCOW equivalent of workloads/minimal.
// Same shape as minimal.bicep but osType: 'Windows' and a Windows nanoserver
// image, with resource requests bumped to typical C-WCOW values.
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
      ccePolicy: ccePolicies.minimal_cwcow
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
            'echo hello c-wcow && ping -n 5 localhost'
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
