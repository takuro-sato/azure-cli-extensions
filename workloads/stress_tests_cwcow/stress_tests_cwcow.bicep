// Confidential WCOW long-running workload with elevated resources.
// Mirrors workloads/stress_tests but stripped of LCOW-specific bits (no SKR
// sidecar, no public IP / ports — those need separate plumbing to verify on
// WCOW and are not the point of this baseline test).
//
// The "stress" is in two places relative to long_lived_cwcow:
// - elevated resource ask (4 CPU / 8 GB) to exercise a larger confidential
//   WCOW UVM allocation path (AUC2 confidential WCOW capacity currently
//   rejects larger asks such as 8 CPU / 16 GB)
// - the container itself does periodic compute + I/O via a `for /l` loop
//   that emits a timestamped tick every ~5s — exercises stdio + the
//   container time source on a long timeline
// - container_log accumulates indefinitely until the harness or operator
//   stops the workload, suitable for stability runs across hours
//
// Pair this workload with Parma vm-tests/harness/lcow_tests/stress_tests_*
// style harness scripts (eventually a wcow_tests/ equivalent) that
// repeatedly start/stop the pod to exercise the runhcs-wcow-hypervisor
// boot path.
//
// Note: digest inlined per minimal_cwcow.bicep rationale.
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
    restartPolicy: 'OnFailure'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.stress_tests_cwcow
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
            '/v:on'
            '/c'
            'for /l %i in (1,1,9999999) do (echo tick %i !time! & ping -n 6 127.0.0.1 > nul)'
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
