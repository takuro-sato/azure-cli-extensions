param location string
param ccePolicies object
param registry string
param repository string
param tag string = ''

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
        name: 'vnet'
        properties: {
          image: '${registry}/${repository}/networking:${empty(tag) ? 'latest' : tag}'
          // Note: vnet containers do not have public IPs, and so it's too
          // difficult to test the server from the runner.  We just do curl
          // check within the container instead.
          command: [
            'curl_from_container.sh'
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
