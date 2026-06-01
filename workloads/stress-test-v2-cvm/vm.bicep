// Confidential VM variant: SEV-SNP confidential VM (DC*as_v* SKU, NOT _cc which
// is for confidential-child via ContainerPlat). Boots Ubuntu directly without
// ContainerPlat.

param deploymentName string

param location string = resourceGroup().location
param vmSize string = 'Standard_DC4as_v6'
param adminUsername string = 'azureuser'
@secure()
param adminPassword string

@secure()
param harnessUrl string

param shareName string
param branch string = 'local'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: uniqueString(subscription().id, resourceGroup().name, location, 'caci-vm-testing-storage-premium')
}

var vmName = '${deploymentName}-vm'
var vnetName = '${deploymentName}-vnet'
var subnetName = 'default'

resource publicIpAddress 'Microsoft.Network/publicIpAddresses@2020-08-01' = {
  name: '${deploymentName}-ip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.0.0.0/16' ] }
    subnets: [
      {
        name: subnetName
        properties: { addressPrefix: '10.0.0.0/24' }
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
          subnet: { id: virtualNetwork.properties.subnets[0].id }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpAddress.id
            properties: { deleteOption: 'Delete' }
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
    hardwareProfile: { vmSize: vmSize }
    securityProfile: {
      securityType: 'ConfidentialVM'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
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
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'cvm'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: { deleteOption: 'Delete' }
        }
      ]
    }
    osProfile: {
      computerName: 'stressv2cvm'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        patchSettings: {
          assessmentMode: 'ImageDefault'
          patchMode: 'ImageDefault'
        }
      }
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

resource runCommand 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  name: 'runCommand'
  location: location
  parent: virtualMachine
  properties: {
    source: {
      script: join([
        '#!/bin/bash'
        'exec >> /tmp/stress-test-v2.log 2>&1'
        'set -ex'
        'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 fio sysbench cifs-utils curl 2>/dev/null'
        'mkdir -p /var/www && cd /var/www'
        'curl -sSfL -o stress_test_v2.py "${harnessUrl}"'
        'chmod +x stress_test_v2.py'
        'export LOCATION="${location}"'
        'export PLATFORM=regular-cvm'
        'export BRANCH="${branch}"'
        'export VM_SKU="${vmSize}"'
        'export CONFIDENTIAL=true'
        'export storage_account="${storageAccount.name}"'
        'export share_name="${shareName}"'
        'export storage_key="${storageAccount.listKeys().keys[0].value}"'
        'python3 ./stress_test_v2.py'
      ], '\n')
    }
  }
}
