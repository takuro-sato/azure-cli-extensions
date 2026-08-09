// Confidential WCOW equivalent of workloads/server.
//
// This workload uses one confidential Windows container exposing an HTTP
// server on a public IP. It uses the Windows Server Core IIS image, whose
// built-in ServiceMonitor entrypoint serves the default IIS page on :80 — no
// command override needed.
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
      ccePolicy: ccePolicies.server_cwcow
    }
    ipAddress: {
      ports: [
        {
          protocol: 'TCP'
          port: 80
        }
      ]
      type: 'Public'
    }
    containers: [
      {
        name: 'primary'
        properties: {
          // Pin by digest by default: the c-aci-testing VM harness resolves
          // tag refs via `oras manifest fetch --platform linux/amd64`
          // (utils/vm.py:resolve_manifest_hash), which has no match in the
          // Windows IIS manifest list and fails — a digest ref skips that
          // resolution. Pass a non-empty `tag` to opt into tag resolution.
          image: empty(tag) ? 'mcr.microsoft.com/windows/servercore/iis@sha256:de0226db25c7077b380bfb44b72f4cd583cda3fc1e70bf6aecaa32cd0f3dcd3a' : 'mcr.microsoft.com/windows/servercore/iis:${tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          ports: [
            {
              protocol: 'TCP'
              port: 80
            }
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
