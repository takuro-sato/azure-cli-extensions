param location string
param registry string
param repository string
param tag string
param ccePolicies object

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.ccf_verify_uvm
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${registry}/${repository}/ccf_verify_uvm:${empty(tag) ? 'latest': tag}'
          resources: {
            requests: {
              memoryInGB: 2
              cpu: 2
            }
          }
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
