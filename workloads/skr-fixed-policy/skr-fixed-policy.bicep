param location string
param registry string
param tag string
param ccePolicies object
param managedIDGroup string = resourceGroup().name
param managedIDName string

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
    restartPolicy: 'Never'
    ipAddress: {
      ports: [
        {
          protocol: 'TCP'
          port: 8000
        }
      ]
      type: 'Public'
    }
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.skr_fixed_policy
    }
    imageRegistryCredentials: [
      {
        server: registry
        identity: resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)
      }
    ]
    containers: [
      {
        name: 'proxy'
        properties: {
          image: '${registry}/prebuilt-test-containers/skr_proxy:${empty(tag) ? 'skr-fixed-policy': tag}'
          ports: [
            {
              protocol: 'TCP'
              port: 8000
            }
          ]
          resources: {
            requests: {
              memoryInGB: 4
              cpu: 1
            }
          }
        }
      }
      {
        name: 'http-sidecar'
        properties: {
          image: 'mcr.microsoft.com/aci/skr:2.14'
          ports: [
            {
              protocol: 'TCP'
              port: 8080
            }
          ]
          environmentVariables: [
            {
              name: 'LogLevel'
              value: 'debug'
            }
            {
              name: 'SkrSideCarArgs'
              value: base64('{"maaconfig":{"user_agent":"confidential-aci-testing"}}')
            }
          ]
          resources: {
            requests: {
              memoryInGB: 4
              cpu: 1
            }
          }
        }
      }
      {
        name: 'grpc-sidecar'
        properties: {
          image: 'mcr.microsoft.com/aci/skr:2.14'
          environmentVariables: [
            {
              name: 'ServerType'
              value: 'grpc'
            }
            {
              name: 'Port'
              value: '50000'
            }
            {
              name: 'LogLevel'
              value: 'debug'
            }
            {
              name: 'SkrSideCarArgs'
              value: base64('{"maaconfig":{"user_agent":"confidential-aci-testing"}}')
            }
          ]
          ports: [
            {
              protocol: 'TCP'
              port: 50000
            }
          ]
          resources: {
            requests: {
              memoryInGB: 4
              cpu: 1
            }
          }
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
