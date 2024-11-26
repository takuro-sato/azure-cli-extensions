using './primary-sidecar-b.bicep'

// Image info
param registry=''

param repository_primary=''
param repository_sidecar=''

param tag=''

// Deployment info
param location=''
param ccePolicies={
  primary_sidecar_b: ''
}
param managedIDName=''
