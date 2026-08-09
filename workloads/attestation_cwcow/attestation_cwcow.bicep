// Windows equivalent of workloads/attestation: a primary client calls a
// colocated SKR sidecar and prints the MAA response for workflow validation.
param location string
param ccePolicies object

param registry string
param repository string
param tag string
param attestationEndpoint string

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
      ccePolicy: ccePolicies.attestation_cwcow
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers' : repository}/attestation-cwcow:${empty(tag) ? 'latest' : tag}'
          environmentVariables: [
            {
              name: 'ATTESTATION_ENDPOINT'
              value: attestationEndpoint
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
      {
        name: 'attestation'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/skr-windows:latest'
          command: [
            'C:\\app\\skr.exe'
          ]
          ports: [
            {
              protocol: 'TCP'
              port: 8080
            }
          ]
          environmentVariables: [
            {
              name: 'Port'
              value: '8080'
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
              memoryInGB: 1
              cpu: 1
            }
          }
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
