using './esan.bicep'

// Image info
param registry=''
param repository=''
param tag=''

// Deployment info
param location='germanynorth'
param ccePolicies={
  esan: ''
}

// Germany North ESAN resources provisioned in the dashboard subscription
// (6532c66d / RG c-aci-dashboard-e2e). ESAN volume, managed identity, and the
// BYO-VNet subnet are all co-located in germanynorth to match the CG region.
param elasticSanVolumeResourceId='/subscriptions/6532c66d-e613-488d-9d2c-f7d4fbf114e7/resourceGroups/c-aci-dashboard-e2e/providers/Microsoft.ElasticSan/elasticSans/esan-germanynorth/volumeGroups/esan-germanynorth-vg/volumes/esan-germanynorth-vol'
param managedIdentityResourceId='/subscriptions/6532c66d-e613-488d-9d2c-f7d4fbf114e7/resourceGroups/c-aci-dashboard-e2e/providers/Microsoft.ManagedIdentity/userAssignedIdentities/cacidashboard-germanynorth'
param managedIdentityClientId='47a19705-7612-4de1-896d-3709bd4ff856'
param subnetResourceId='/subscriptions/6532c66d-e613-488d-9d2c-f7d4fbf114e7/resourceGroups/c-aci-dashboard-e2e/providers/Microsoft.Network/virtualNetworks/esan-vnet-germanynorth/subnets/acisubnet'
