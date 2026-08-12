param location string
param registry string
param repository string
param tag string
param imageName string = 'info-cwcow-ws2025'

param zone string
param useVnet bool = false
param managedIDGroup string = resourceGroup().name
param managedIDName string = ''

param cpu int = 2
param memoryInGb int = 4

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: 'aci-long-lived-vnet-${location}'
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: virtualNetwork
  name: 'acisubnet'
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: managedIDName
  scope: resourceGroup(managedIDGroup)
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  identity: !empty(managedIDName)
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)}': {}
        }
      }
    : {
        type: 'None'
      }
  zones: empty(zone)
    ? null
    : [
        zone
      ]
  properties: {
    osType: 'Windows'
    subnetIds: useVnet ? [{ id: subnet.id }] : []
    restartPolicy: 'Never'
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers' : repository}/${imageName}:${empty(tag) ? 'latest' : tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          environmentVariables: [
            {
              name: 'TEST_MANAGED_IDENTITY'
              value: !empty(managedIDName) ? '1' : ''
            }
            {
              name: 'MANAGED_IDENTITY_PRINCIPAL_ID'
              value: !empty(managedIDName) ? managedIdentity.properties.principalId : ''
            }
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
