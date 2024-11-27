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
            cat /proc/cpuinfo | grep -i "model name" | head -n 1
            apt update >& /dev/null
            apt install fio sysbench -y >& /dev/null
            echo --------- 4 threads ------------
            echo CPU
            sysbench --threads=4 --time=10 cpu --cpu-max-prime=15000 run | grep "events per second"
            fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=64k --iodepth=64 --readwrite=randrw --size=4G | grep -E 'READ|WRITE'
            echo Memory
            sysbench memory --time=10 run --threads=4 | grep "MiB/sec"
            echo --------- 2 threads ------------ 0, 2
            echo CPU
            taskset --cpu-list 0,2 sysbench --threads=2 --time=10 cpu --cpu-max-prime=15000 run | grep "events per second"
            echo Memory
            taskset --cpu-list 0,2 sysbench memory --time=10 run --threads=2 | grep "MiB/sec"
            echo --------- 2 threads ------------ 0, 1
            echo CPU
            taskset --cpu-list 0,1 sysbench --threads=2 --time=10 cpu --cpu-max-prime=15000 run | grep "events per second"
            echo Memory
            taskset --cpu-list 0,1 sysbench memory --time=10 run --threads=2 | grep "MiB/sec"
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
