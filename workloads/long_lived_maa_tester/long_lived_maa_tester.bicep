param location string
param registry string
param repository string
param tag string
param ccePolicies object
param skrTag string = '2.14'
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
    restartPolicy: 'OnFailure'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.long_lived_maa_tester
    }
    imageRegistryCredentials: [
      {
        server: registry
        identity: resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)
      }
    ]
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${registry}/${empty(repository) ? 'maa-tester' : repository}:${empty(tag) ? 'latest': tag}'
          ports: []
          resources: {
            requests: {
              // float literals or float() calls are not available in bicep
              memoryInGB: json('0.5')
              cpu: json('0.5')
            }
          }
          environmentVariables: [
            {
              name: 'KUSTO_CONNECTION_STRING'
              value: 'https://acckusto.southcentralus.kusto.windows.net/'
            }
            {
              name: 'KUSTO_DATABASE'
              value: 'ACCTEST'
            }
            {
              name: 'KUSTO_TABLE'
              value: 'CACIMAATestTrace'
            }
            {
              name: 'CLIENT_REGION'
              value: location
            }
          ]
          volumeMounts: [
            {
              name: 'skr-logs'
              mountPath: '/var/log/skr'
            }
          ]
        }
      }
      {
        name: 'skr'
        properties: {
          image: 'mcr.microsoft.com/aci/skr:${skrTag}'
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
              name: 'LogFile'
              value: '/var/log/skr/skr.log'
            }
            {
              name: 'SkrSideCarArgs'
              value: base64('{"maaconfig":{"user_agent":"confidential-aci-testing"}}')
            }
          ]
          resources: {
            requests: {
              // float literals or float() calls are not available in bicep
              memoryInGB: json('0.5')
              cpu: json('0.5')
            }
          }
          volumeMounts: [
            {
              name: 'skr-logs'
              mountPath: '/var/log/skr'
            }
          ]
        }
      }
    ]
    volumes: [
      {
        name: 'skr-logs'
        emptyDir: {}
      }
    ]
  }
}

output ids array = [containerGroup.id]
