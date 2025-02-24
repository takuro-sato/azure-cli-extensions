param location string
param registry string
param repo_base string = 'virtualclient'
param tag string
param managedIDGroup string = resourceGroup().name
param managedIDName string
param ccePolicies object

param totalCpus int = 4
param totalMemoryGB int = 16

param profileName string = ''

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
      ccePolicy: ccePolicies.virtualclient
    }
    containers: [
      {
        name: 'virtualclient'
        properties: {
          image: '${registry}/${empty(repo_base) ? 'virtualclient' : repo_base}:${empty(tag) ? 'latest' : tag}'
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
            {
              name: 'PROFILE_NAME'
              value: profileName
            }
          ]
          resources: {
            requests: {
              memoryInGB: totalMemoryGB
              cpu: totalCpus
            }
          }
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
