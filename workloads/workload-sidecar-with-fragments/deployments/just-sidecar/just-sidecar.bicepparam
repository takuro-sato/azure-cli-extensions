using './just-sidecar.bicep'

// Image info
param registry=''

param repository_sidecar=''

param tag=''

// Deployment info
param location=''
param ccePolicies={
  just_sidecar: ''
}
param managedIDName=''
