param location string
param ccePolicies object
param managedIDGroup string = resourceGroup().name
param managedIDName string

param registry string
param repository string
param tag string

param cpu int = 1
param memoryInGb int = 4

param useVnet bool = false

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: uniqueString(subscription().id, resourceGroup().name, location, 'caci-testing-storage')
}

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
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)}': {}
    }
  }
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    subnetIds: useVnet ? [{ id: subnet.id }] : []
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.volume
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers/stress-tests-noserver-ubuntu' : repository}:${empty(tag) ? 'latest' : tag}'
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
            sleep 1
            cd /var/www
            ./io_latency_bench_like_ccf.py -w /mnt/volume
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
          shareName: 'testshare'
          storageAccountName: storageAccount.name
          storageAccountKey: storageAccount.listKeys().keys[0].value
          readOnly: false
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
