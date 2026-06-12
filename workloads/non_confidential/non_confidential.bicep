param location string

param registry string
param repository string
param tag string

param zone string
param useVnet bool

param cpu int = 1
param memoryInGb int = 4

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: 'aci-long-lived-vnet-${location}'
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: virtualNetwork
  name: 'acisubnet'
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  zones: empty(zone)
    ? null
    : [
        // Despite this being a "zones" property, ACI only supports one availability zone for a container group resource.
        zone
      ]
  properties: {
    osType: 'Linux'
    subnetIds: useVnet ? [{ id: subnet.id }] : []
    restartPolicy: 'Never'
    containers: [
      {
        name: 'ubuntu'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers' : repository}/info:${empty(tag) ? 'latest' : tag}'
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
