param location string
param tag string
param ccePolicies object

@secure()
@description('This should be base64 encoded')
param mysecret string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.secrets
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: 'mcr.microsoft.com/azurelinux/base/core:${empty(tag) ? '3.0' : tag}'
          volumeMounts: [
            {
              name: 'secretvolume'
              mountPath: '/mnt/secrets'
            }
          ]
          resources: {
            requests: {
              memoryInGB: 1
              cpu: 1
            }
          }
          command: [
            'bash'
            '-c'
            '''
            while :; do
              echo ls /mnt/secrets:
              ls -la /mnt/secrets
              echo content:
              cat /mnt/secrets/mysecret
              sleep 5
            done
            '''
          ]
        }
      }
    ]
    volumes: [
      {
        name: 'secretvolume'
        secret: {
          mysecret: mysecret
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
