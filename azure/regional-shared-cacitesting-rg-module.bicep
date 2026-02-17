param location string
param perRegionMsiPrincipalId string

resource cacitestingstorageaci 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: 'cacitestingstorageaci'
}

resource storageBlobDataContributor 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

// Give the per-region managed identity access to the storage account for logs
resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(cacitestingstorageaci.id, perRegionMsiPrincipalId, storageBlobDataContributor.id)
  scope: cacitestingstorageaci
  properties: {
    roleDefinitionId: storageBlobDataContributor.id
    principalId: perRegionMsiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource storageFileDataSMBMIAdmin 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'a235d3ee-5935-4cfb-8cc5-a3303ad5995e'
  scope: subscription()
}

// "Storage File Data SMB MI Admin" access on the storage account too for file mount tests
resource storageFileDataSMBMIAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(cacitestingstorageaci.id, perRegionMsiPrincipalId, storageFileDataSMBMIAdmin.id)
  scope: cacitestingstorageaci
  properties: {
    roleDefinitionId: storageFileDataSMBMIAdmin.id
    principalId: perRegionMsiPrincipalId
    principalType: 'ServicePrincipal'
  }
}
