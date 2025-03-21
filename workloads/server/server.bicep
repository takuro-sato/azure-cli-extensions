param location string
param tag string
param ccePolicies object
param registry string
param repository string

param cpu int = 1
param memoryInGb int = 4

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.server
    }
    ipAddress: {
      ports: [
        {
          protocol: 'TCP'
          port: 80
        }
      ]
      type: 'Public'
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${registry}/${repository}/networking:${empty(tag) ? 'latest' : tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          ports: [
            {
              protocol: 'TCP'
              port: 80
            }
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
