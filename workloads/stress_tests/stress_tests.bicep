param location string
param registry string
param repository string
param tag string
param ccePolicies object
param script string = 'workload_fio'

param totalCpus int = 4
param totalMemoryGB int = 4

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never' // Detect container crashes
    ipAddress: {
      ports: [
        {
          protocol: 'TCP'
          port: 80
        }
      ]
      type: 'Public'
    }
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.stress_tests
    }
    containers: [
      {
        name: 'workload'
        properties: {
          image: '${registry}/${repository}:${empty(tag) ? 'latest' : tag}'
          ports: [
            {
              protocol: 'TCP'
              port: 80
            }
          ]
          environmentVariables: [
            {
              name: 'PORT'
              value: '80'
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
          image: 'mcr.microsoft.com/aci/skr:2.12'
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
