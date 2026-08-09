// Confidential WCOW info + attestation workload.
//
// Mirrors workloads/info (the LCOW info container): runs our repo-prebuilt
// `info-cwcow` image, which dumps Windows guest info AND fetches a raw
// AMD SEV-SNP attestation report via an embedded psputilgo.exe (attest.py). This
// is the WCOW equivalent of the LCOW info container embedding get-snp-report —
// see micromaomao's PR #332 review: "do an attestation report, using a PspUtil
// embedded in the image (like the LCOW info)... output stuff in JSON like
// OUTPUT: {...} so it gets into Kusto via parse_container_output.py".
//
// attest.py emits the legacy ===HOSTNAME===/===EOF=== markers (so the existing
// log check still passes) AND an `OUTPUT: {json}` attestation result.
//
// AUC2-only (real ACI): uses the registry/repository/tag image-ref pattern (like
// workloads/info), not the digest-pin ternary the vm-cwcow workloads need.
param location string
param tag string
param ccePolicies object

param registry string
param repository string
param useVnet bool = false

param cpu int = 2
param memoryInGb int = 4

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: 'aci-long-lived-vnet-${location}'
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: virtualNetwork
  name: 'acisubnet'
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Windows'
    sku: 'Confidential'
    subnetIds: useVnet ? [{ id: subnet.id }] : []
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.info_cwcow
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers' : repository}/info-cwcow:${empty(tag) ? 'latest' : tag}'
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
