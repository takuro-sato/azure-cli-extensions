param location string
param managedIDGroup string = resourceGroup().name
param managedIDName string

param registry string
param repository string
param tag string

param cpu int = 4
param memoryInGb int = 16
param branch string = 'local'

@description('Name of the Azure Files Premium share (created out-of-band by the workflow).')
param shareName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: uniqueString(subscription().id, resourceGroup().name, location, 'caci-nonconf-testing-storage-premium')
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
    restartPolicy: 'Never'
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
          securityContext: {
            privileged: true
          }
          environmentVariables: [
            { name: 'LOCATION', value: location }
            { name: 'PLATFORM', value: 'aci' }
            { name: 'BRANCH', value: branch }
            { name: 'CONFIDENTIAL', value: 'false' }
            { name: 'storage_account', value: storageAccount.name }
            { name: 'share_name', value: shareName }
            { name: 'storage_key', secureValue: storageAccount.listKeys().keys[0].value }
            { name: 'storage_fqdn', value: '${storageAccount.name}.file.${environment().suffixes.storage}' }
          ]
          command: [
            '/usr/bin/python3'
            '/var/www/stress_test_v2.py'
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
