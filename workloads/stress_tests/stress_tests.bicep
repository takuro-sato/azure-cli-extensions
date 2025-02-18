param location string
param registry string
param repo_base string = 'stress_tests'
param tag string
param managedIDGroup string = resourceGroup().name
param managedIDName string
param ccePolicies object
param script string = 'workload_fio'
param useNormalSidecar bool = false

param totalCpus int = 4
param totalMemoryGB int = 4

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
    ipAddress: {
      ports: [
        {
          protocol: 'TCP'
          port: 8000
        }
      ]
      type: 'Public'
    }
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
          image: '${registry}/${empty(repo_base) ? 'stress_tests' : repo_base}/workload:${tag}'
          ports: [
            {
              protocol: 'TCP'
              port: 8000
            }
          ]
          environmentVariables: [
            {
              name: 'PORT'
              value: '8000'
            }
          ]
          resources: {
            requests: {
              memoryInGB: totalMemoryGB-1
              cpu: totalCpus-1
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
          image: 'mcr.microsoft.com/aci/skr:2.7'
          ports: [
            {
              protocol: 'TCP'
              port: 8080
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
