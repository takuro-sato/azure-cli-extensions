param deploymentName string

param location string = resourceGroup().location
param vmSize string = 'Standard_DC8as_v5'
param adminUsername string = 'azureuser'
@secure()
param adminPassword string

var vnetName = '${deploymentName}-vnet'
var vmName = '${deploymentName}-vm'
var subnetName = 'default'

resource publicIpAddress 'Microsoft.Network/publicIpAddresses@2020-08-01' = {
  name: '${deploymentName}-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2022-11-01' = {
  name: '${deploymentName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpAddress.id
            properties: {
              deleteOption: 'Delete'
            }
          }
        }
      }
    ]
    enableAcceleratedNetworking: true
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 128
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          securityProfile: {
            securityEncryptionType: 'DiskWithVMGuestState'
          }
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'cvm'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'ConfidentialVM'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    osProfile: {
      computerName: 'perfvm'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        patchSettings: {
          assessmentMode: 'ImageDefault'
          patchMode: 'ImageDefault'
        }
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource runCommand 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  name: 'runCommand'
  location: location
  parent: virtualMachine
  properties: {
    source: {
      script: join(
        [
          '/bin/bash'
          '-c'
          '\'\n'
          '''
            uname -a
            cat /proc/cpuinfo | grep -i "model name" | head -n 1
            apt update >& /dev/null
            apt install fio sysbench -y >& /dev/null
            echo --------- 4 threads ------------
            echo CPU
            sysbench --threads=4 --time=10 cpu --cpu-max-prime=15000 run | grep "events per second"
            fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=64k --iodepth=64 --readwrite=randrw --size=4G | grep -E "READ|WRITE"
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
          '\n\' > /tmp/perf.log 2>&1'
        ],
        ' '
      )
    }
  }
}
