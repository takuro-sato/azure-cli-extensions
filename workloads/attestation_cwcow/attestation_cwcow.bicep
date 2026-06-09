// Confidential WCOW attestation workload.
//
// Windows analogue of workloads/attestation, but built on the SAME mechanism as
// the LCOW `info` container rather than the LCOW `attestation` container:
//   * LCOW `attestation` uses an `mcr.microsoft.com/aci/skr` sidecar to obtain a
//     MAA-signed JWT. There is no Windows SKR sidecar, so that path is NOT
//     portable to WCOW.
//   * Instead, this runs our repo-prebuilt `attestation-cwcow` image, which
//     embeds `psputilgo.exe`. That tool calls amdsnppspapi.dll
//     (SnpPspIsSnpMode / SnpPspFetchAttestationReport, lazy-loaded from the
//     UVM's System32) to fetch a RAW AMD SEV-SNP attestation report from inside
//     the confidential Windows guest. Successfully fetching a hardware report is
//     itself the attestation assertion.
//
// The container's attest.py emits `OUTPUT: {json}` (snp_mode/report_fetched/
// cert_url) on success and `ERROR: ...` + `OUTPUT: {...,"snp_mode":false}` on
// failure, which scripts/parse_container_output.py scrapes.
//
// AUC2-only (real ACI): this is never deployed via the OneBox VM harness, so it
// uses the registry/repository/tag image-ref pattern (like workloads/info)
// rather than the digest-pin ternary the vm-cwcow workloads need.
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
      ccePolicy: ccePolicies.attestation_cwcow
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers' : repository}/attestation-cwcow:${empty(tag) ? 'latest' : tag}'
          // No command override: the image's default CMD runs `python attest.py`,
          // which fetches the SNP report and emits OUTPUT/ERROR then exits.
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
