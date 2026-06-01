// Bicep template for the stress-test-v2 ContainerPlat-on-VM (confidential) test.
//
// IMPORTANT: This template is NOT meant to be deployed as a real ACI container
// group. It is only consumed by `c-aci-testing vm generate_scripts` / `vm runc`
// to produce LCOW configs for ContainerPlat on a Windows VM.

param location string = 'unknown'
param ccePolicies object

param registry string
param repository string
param tag string

param branch string = 'local'

@description('VM SKU label, traced into Kusto for breakdown.')
param vmSku string = ''
@description('ContainerPlat blob name label, traced into Kusto.')
param cplatBlob string = ''

param storageAccountName string
@secure()
param storageAccountKey string
param storageAccountFqdn string
param shareName string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.stress_test_v2_cplat_vm
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'cacidashboardaci.azurecr.io' : registry}/${empty(repository) ? 'prebuilt-test-containers/stress-tests-noserver-ubuntu' : repository}:${empty(tag) ? 'latest' : tag}'
          resources: {
            requests: {
              memoryInGB: 16
              cpu: 4
            }
          }
          securityContext: {
            privileged: true
          }
          environmentVariables: [
            { name: 'LOCATION', value: location }
            { name: 'PLATFORM', value: 'cplat-vm' }
            { name: 'BRANCH', value: branch }
            { name: 'VM_SKU', value: vmSku }
            { name: 'CPLAT_BLOB', value: cplatBlob }
            { name: 'CONFIDENTIAL', value: 'true' }
            { name: 'storage_account', value: storageAccountName }
            { name: 'share_name', value: shareName }
            { name: 'storage_key', value: storageAccountKey }
            { name: 'storage_fqdn', value: storageAccountFqdn }
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
