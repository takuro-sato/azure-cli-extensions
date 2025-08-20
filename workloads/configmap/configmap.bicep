param location string
param tag string
param ccePolicies object

param myconfig string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2024-05-01-preview' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.configmap
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: 'mcr.microsoft.com/azurelinux/base/core:${empty(tag) ? '3.0' : tag}'
          resources: {
            requests: {
              memoryInGB: 1
              cpu: 1
            }
          }
          configMap: {
            keyValuePairs: {
              myconfig: myconfig
            }
          }
          command: [
            'bash'
            '-c'
            '''
            while :; do
              echo ls /mnt/configmap/primary:
              ls -la /mnt/configmap/primary
              echo content:
              cat /mnt/configmap/primary/myconfig
              sleep 5
            done
            '''
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
