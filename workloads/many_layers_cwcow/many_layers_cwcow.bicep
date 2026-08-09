// Confidential WCOW many-layers workload.
//
// Windows analogue of workloads/many_layers. The LCOW version pulls a deep
// multi-layer image and just echoes a marker — the point is to exercise the
// guest's overlay/layer handling, not to run anything meaningful.
//
// The dedicated `many-layers-cwcow` image adds exactly 20 non-empty filesystem
// layers above its Nano Server base. This workload asserts that the resulting
// confidential Windows image mounts and boots.
//
// AUC2-only (real ACI): uses the registry/repository/tag image-ref pattern (like
// workloads/info), not the digest-pin ternary the vm-cwcow workloads need.
param location string
param ccePolicies object

param registry string
param repository string
param tag string

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
      ccePolicy: ccePolicies.many_layers_cwcow
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers' : repository}/many-layers-cwcow:${empty(tag) ? 'latest' : tag}'
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
