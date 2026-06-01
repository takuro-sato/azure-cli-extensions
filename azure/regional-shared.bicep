param location string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: 'aci-long-lived-vnet-${location}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: virtualNetwork
  name: 'acisubnet'
  properties: {
    addressPrefix: '10.0.0.0/24'
    defaultOutboundAccess: false
    delegations: [
      {
        name: 'aciDelegation'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
        locations: [
          location
        ]
      }
    ]
  }
}

// This identity is used to attach to deployed ACI and VM resource, one per region.
// This is not the cacidashboard identity - that is the single identity used by
// runner to deploy these containers/VMs.
resource perRegionManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'cacidashboard-${location}'
  location: location
  properties: {
    isolationScope: 'Regional'
  }
}

resource cacidashboard 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: 'cacidashboard'
}

resource managedIdentityOperator 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'f1a07417-d97a-45cb-824c-7a7467783830'
  scope: subscription()
}

// Give cacidashboard access to the pre-region managed identity to use for ACI / VM deployments
resource managedIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(perRegionManagedIdentity.id, cacidashboard.id, managedIdentityOperator.id)
  scope: perRegionManagedIdentity
  properties: {
    roleDefinitionId: managedIdentityOperator.id
    principalId: cacidashboard.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: 'cacidashboardaci'
}

resource acrPull 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  scope: subscription()
}

// Give the per-region managed identity access to pull from ACR
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(containerRegistry.id, perRegionManagedIdentity.id, acrPull.id)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPull.id
    principalId: perRegionManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource regionalStorageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: uniqueString(subscription().id, resourceGroup().name, location, 'caci-testing-storage')
  location: location
  kind: 'StorageV2'
  tags: {
    purpose: 'caci-testing-storage'
  }
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Enabled'
    azureFilesIdentityBasedAuthentication: {
      smbOAuthSettings: {
        isSmbOAuthEnabled: true
      }
      directoryServiceOptions: 'None'
    }
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: subnet.id
          action: 'Allow'
        }
      ]
    }
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2025-08-01' = {
  parent: regionalStorageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: false
    }
  }
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-08-01' = {
  parent: fileService
  name: 'testshare'
  properties: {
    accessTier: 'Hot'
    enabledProtocols: 'SMB'
  }
}

// Premium FileStorage account for stress-test-v2 ACI tests (confidential variant).
// Shares are created at pipeline run time and deleted afterwards to save cost.
resource fioAciPremiumStorageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: uniqueString(subscription().id, resourceGroup().name, location, 'caci-testing-storage-premium')
  location: location
  kind: 'FileStorage'
  tags: {
    purpose: 'caci-testing-storage-premium'
  }
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
  }
}

resource fioAciPremiumFileService 'Microsoft.Storage/storageAccounts/fileServices@2025-08-01' = {
  parent: fioAciPremiumStorageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: false
    }
  }
}

// Premium FileStorage account for stress-test-v2 regular-VM tests (separate from ACI account
// to allow ACI and VM tests to run in parallel without share contention).
resource fioVmPremiumStorageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: uniqueString(subscription().id, resourceGroup().name, location, 'caci-vm-testing-storage-premium')
  location: location
  kind: 'FileStorage'
  tags: {
    purpose: 'caci-vm-testing-storage-premium'
  }
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
  }
}

resource fioVmPremiumFileService 'Microsoft.Storage/storageAccounts/fileServices@2025-08-01' = {
  parent: fioVmPremiumStorageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: false
    }
  }
}

// Premium FileStorage account for stress-test-v2 non-confidential ACI tests. Separate from the
// confidential ACI account so that conf and non-conf runs in the same region don't contend
// on the same storage account when running in parallel.
resource fioAciNonconfPremiumStorageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: uniqueString(subscription().id, resourceGroup().name, location, 'caci-nonconf-testing-storage-premium')
  location: location
  kind: 'FileStorage'
  tags: {
    purpose: 'caci-nonconf-testing-storage-premium'
  }
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
  }
}

resource fioAciNonconfPremiumFileService 'Microsoft.Storage/storageAccounts/fileServices@2025-08-01' = {
  parent: fioAciNonconfPremiumStorageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: false
    }
  }
}

module cacitestingRgModule 'regional-shared-cacitesting-rg-module.bicep' = {
  name: 'regional-shared-cacitesting-rg-${location}'
  scope: resourceGroup('c-aci-testing')
  params: {
    location: location
    perRegionMsiPrincipalId: perRegionManagedIdentity.properties.principalId
  }
}
