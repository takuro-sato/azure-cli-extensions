param location string
param ccePolicies object
param managedIDGroup string = resourceGroup().name
param managedIDName string

param cpu int = 1
param memoryInGb int = 4

@secure()
param key string

// resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
//   name: 'cacidashboardvolumetest'
// }

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
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.volume
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: 'mcr.microsoft.com/mirror/docker/library/ubuntu:24.04'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          volumeMounts: [
            {
              name: 'volume'
              mountPath: '/mnt/volume'
            }
          ]
          command: [
            '/bin/bash'
            '-c'
            '''
            set -ex
            cd /mnt/volume
            TIMESTAMP_NS=$(date '+%Y-%m-%dT%T.%N')
            echo "Hello" >> "$TIMESTAMP_NS.txt"
            ls -la
            set +x
            echo "File name: $TIMESTAMP_NS.txt"
            sleep infinity
            '''
          ]
        }
      }
    ]
    volumes: [
      {
        name: 'volume'
        azureFile: {
          shareName: 'share'
          storageAccountName: 'twcacitestfilesharewus'
          storageAccountKey: key
          readOnly: false
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
