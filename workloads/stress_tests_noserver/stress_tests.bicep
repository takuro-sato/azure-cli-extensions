param location string
param registry string
param repo_base string = 'stress_tests_noserver'
param tag string
param managedIDGroup string = resourceGroup().name
param managedIDName string
param ccePolicies object
param script string = 'workload_fio'
param useNormalSidecar bool = false

param cpu int = 4
param memoryInGb int = 4

var sidecarImage = useNormalSidecar ? 'mcr.microsoft.com/aci/skr:2.7' : '${registry}/${repo_base}/sidecar:${tag}'

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)}': {}
    }
  }
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never' // Detect container crashes
    imageRegistryCredentials: [
      {
        server: registry
        identity: resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)
      }
    ]
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.stress_tests
    }
    containers: [
      {
        name: 'workload'
        properties: {
          image: '${registry}/${empty(repo_base) ? 'stress_tests_noserver' : repo_base}/workload:${tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          command: [
            '/bin/bash'
            '${script}.sh'
          ]
        }
      }
      {
        name: 'sidecar'
        properties: {
          image: sidecarImage
          ports: [
            {
              protocol: 'TCP'
              port: 8080
            }
          ]
          resources: {
            requests: {
              memoryInGB: 2
              cpu: 2
            }
          }
          // We do not have the correct attestation endpoint in this workload for skr to work properly, and it will
          // just terminate.
          command: useNormalSidecar ? [
            '/bin/sleep'
            'infinity'
          ] : null
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
