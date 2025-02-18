param location string
param registry string
param tag string
param ccePolicies object
param managedIDGroup string = resourceGroup().name
param managedIDName string

param cpu int = 1
param memoryInGb int = 2

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
    imageRegistryCredentials: [
      {
        server: registry
        identity: resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)
      }
    ]
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.info
    }
    containers: [
      {
        name: 'ubuntu'
        properties: {
          image: '${registry}/info:${empty(tag) ? 'latest': tag}'
          command: [
            'sh'
            '-c'
            'uname -a && dmesg | grep "Kernel command line" && dmesg | grep "Host Build" && cat /proc/cpuinfo && echo snp-report: && verbose-report'
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

output ids array = [containerGroup.id]
