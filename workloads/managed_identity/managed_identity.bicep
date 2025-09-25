param location string
param registry string
param repository string
param tag string
param ccePolicies object
param useVnet bool = false
param managedIDGroup string = resourceGroup().name
param managedIDName string

param cpu int = 1
param memoryInGb int = 1

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
    subnetIds: useVnet ? [{ id: subnet.id }] : null
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.managed_identity
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
          image: '${registry}/${empty(repository) ? 'ubuntu-with-curl' : repository}:${empty(tag) ? '24.04': tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          command: [
            '/bin/bash'
            '-c'
            '''
            set +e
            echo "Testing managed identity..."
            tries=0
            success=false
            while [ "$tries" -lt 5 ]; do
              tries=$((tries + 1))
              # Important: do not expose output to stdout as the container log
              # is fetched and displayed by the pipeline.
              timeout 10 \
                curl --fail -s -H "Metadata: true" -v \
                "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
                -o /dev/null
              if [ $? -eq 0 ]; then
                success=true
                break
              fi
              echo "Attempt $tries failed, retrying..."
              sleep 5
            done
            if [ "$success" = "false" ]; then
              echo "ERROR: Failed to retrieve token from IMDS after $tries attempts"
              echo "OUTPUT: {\"attempts\": $tries, \"success\": false}"
              sleep infinity
            fi
            echo "IMDS request successful"
            echo "OUTPUT: {\"attempts\": $tries, \"success\": true}"
            sleep infinity
            '''
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
