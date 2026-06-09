// Confidential WCOW many-layers workload.
//
// Windows analogue of workloads/many_layers. The LCOW version pulls a deep
// multi-layer image and just echoes a marker — the point is to exercise the
// guest's overlay/layer handling, not to run anything meaningful.
//
// We reuse the repo-prebuilt `attestation-cwcow` image, which is intentionally
// near the confidential-WCOW cimfs layer ceiling (~12 layers: servercore python
// installer collapsed into a nanoserver base + COPY'd python + psputilgo +
// attest.py). The command is overridden to a trivial marker so this workload
// asserts only that a deep-layer confidential Windows image mounts and boots —
// it does NOT depend on attestation succeeding (that is attestation_cwcow's
// job).
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
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers' : repository}/attestation-cwcow:${empty(tag) ? 'latest' : tag}'
          command: [
            'python'
            '-c'
            'print("===MANY_LAYERS_OK===")'
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
