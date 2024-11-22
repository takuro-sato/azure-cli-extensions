param location string
param registry string
param tag string
param managedIDGroup string = resourceGroup().name
param managedIDName string

param cpu int = 4
param memoryInGb int = 8

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
    restartPolicy: 'Never'
    imageRegistryCredentials: [
      {
        server: registry
        identity: resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)
      }
    ]

    containers: [
      {
        name: 'ubuntu'
        properties: {
          image: '${registry}/ubuntu:${empty(tag) ? '20.04': tag}'
          command: [
            '/bin/bash'
            '-c'
            '''
            uname -a
            dmesg | grep "Kernel command line"
            dmesg | grep "Host Build"
            cat /proc/cpuinfo
            apt update
            apt install fio sysbench -y
            echo --------- 4 threads ------------
            sysbench --threads=4 --time=10 --test=cpu --cpu-max-prime=15000 run
            fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=64k --iodepth=64 --readwrite=randrw --size=4G
            sysbench memory --time=10 run --threads=4
            echo --------- 2 threads ------------
            sysbench --threads=2 --time=10 --test=cpu --cpu-max-prime=15000 run
            sysbench memory --time=10 run --threads=2
            '''
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
