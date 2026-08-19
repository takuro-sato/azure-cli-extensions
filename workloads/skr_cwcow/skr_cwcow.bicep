// Confidential WCOW equivalent of workloads/skr.
//
// The Linux skr workload runs three containers in one group: a Python proxy
// (public IP, :8000) in front of two localhost-only skr sidecars (an HTTP one
// on :8080 and a gRPC one on :50000). This workload omits that proxy +
// dual-sidecar layout and instead runs a confidential Windows skr image
// (cacidashboardaci.azurecr.io/skr-windows) that serves the HTTP interface
// directly on 0.0.0.0:8000, exposed via a public IP. There is no gRPC path
// here — the gRPC endpoints in the Linux workload are synthesised by the proxy
// (grpcurl), which we dropped along with the proxy container.
//
// Fixed allow_all policy (see skr_cwcow.bicepparam / policy_skr_cwcow.rego):
// generated WCOW policies need confcom 1.3.0+wcow + Windows Docker (not
// available on ubuntu-latest — see vm-cwcow.yml / workload-info-cwcow.yml), so
// like every other C-WCOW workload this uses allow_all. The committed rego is
// loaded verbatim so its sha256 (the SEV-SNP host_data) is deterministic and
// the key-release tests can bind their release policy to it.
param location string
param registry string
param tag string
param ccePolicies object
param managedIDGroup string = resourceGroup().name
param managedIDName string

param cpu int = 2
param memoryInGb int = 4

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/824db9f9-0ff1-49f2-ab3e-4b72dfb9dd6a/resourceGroups/c-aci-dashboard/providers/Microsoft.ManagedIdentity/userAssignedIdentities/cacidashboard-${location}': {}
    }
  }
  properties: {
    osType: 'Windows'
    sku: 'Confidential'
    restartPolicy: 'Never'
    ipAddress: {
      ports: [
        {
          protocol: 'TCP'
          port: 8000
        }
      ]
      type: 'Public'
    }
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.skr_cwcow
    }
    // imageRegistryCredentials: [
    //   {
    //     server: registry
    //     identity: resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)
    //   }
    // ]
    containers: [
      {
        name: 'skr'
        properties: {
          // The confidential Windows skr image. By default skr.exe binds to
          // localhost; -dangerouslySetListenAddr 0.0.0.0 makes it serve the
          // HTTP interface on all interfaces so the public IP can reach it on
          // the port given by the `Port` env var.
          image: '${registry}/skr-windows:${empty(tag) ? 'latest' : tag}'
          command: [
            'C:\\app\\skr.exe'
          ]
          ports: [
            {
              protocol: 'TCP'
              port: 8000
            }
          ]
          environmentVariables: [
            {
              name: 'Port'
              value: '8000'
            }
            {
              name: 'LogLevel'
              value: 'debug'
            }
            {
              name: 'SkrSideCarArgs'
              value: base64('{"maaconfig":{"user_agent":"confidential-aci-testing"}}')
            }
          ]
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
        }
      }
      // {
      //   name: 'powershell'
      //   properties: {
      //     image: 'mcr.microsoft.com/windows/servercore:ltsc2025'
      //     command: [
      //       'ping.exe'
      //       '-t'
      //       '127.0.0.1'
      //     ]
      //     resources: {
      //       requests: {
      //         memoryInGB: 1
      //         cpu: 1
      //       }
      //     }
      //   }
      // }
    ]
  }
}

output ids array = [containerGroup.id]
