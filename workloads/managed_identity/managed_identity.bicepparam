using './managed_identity.bicep'

// Image info
param registry=''
param tag=''

// Deployment info
param location='westeurope'
param ccePolicies={
  managed_identity: ''
}
param managedIDName='cacidashboard'
