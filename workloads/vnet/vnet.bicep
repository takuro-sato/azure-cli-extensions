param location string
param ccePolicies object
param cpu int = 1
param memoryInGb int = 2

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    subnetIds: [{id: subnet.id}]
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.vnet
    }
    containers: [
      {
        name: 'ubuntu'
        properties: {
          image: 'quay.io/curl/curl:8.11.0'
          command: [
            'sh'
            '-c'
            'curl -v http://example.com && echo "It worked"'
          ]
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

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${deployment().name}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  parent: virtualNetwork
  name: '${deployment().name}-subnet'
  properties: {
    addressPrefix: '10.0.0.0/24'
    delegations: [
      {
        name: 'aciDelegation'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
