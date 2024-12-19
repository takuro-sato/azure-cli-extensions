param location string
param tag string
param ccePolicies object

param cpu int = 1
param memoryInGb int = 4
param zone string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  zones: [
    // Despite this being a "zones" property, ACI only supports one availability zone for a container group resource.
    zone
  ]
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.availability_zones
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: 'mcr.microsoft.com/mcr/hello-world:${empty(tag) ? 'latest': tag}'
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
