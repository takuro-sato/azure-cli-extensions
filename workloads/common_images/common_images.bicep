param location string
param ccePolicies object

param cpu int = 1
param memoryInGb int = 2

resource containerGroupUbuntu2204 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: '${deployment().name}-ubuntu-2204'
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.common_images_ubuntu_2204
    }
    containers: [
      {
        name: 'ubuntu2204'
        properties: {
          image: 'mcr.microsoft.com/mirror/docker/library/ubuntu:22.04'
          command: [
            '/bin/bash'
            '-c'
            'echo "Container ubuntu 22.04 Started"'
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

resource containerGroupUbuntu2404 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: '${deployment().name}-ubuntu-2404'
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.common_images_ubuntu_2404
    }
    containers: [
      {
        name: 'ubuntu2404'
        properties: {
          image: 'mcr.microsoft.com/mirror/docker/library/ubuntu:24.04'
          command: [
            '/bin/bash'
            '-c'
            'echo "Container ubuntu 24.04 Started"'
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

output ids array = [
  containerGroupUbuntu2204.id
  containerGroupUbuntu2404.id
]
