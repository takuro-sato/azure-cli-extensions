using './vnet.bicep'

// Deployment info
param location=''
param ccePolicies={
  vnet: ''
}

// Image info
param registry=''
param repository=''
param tag=''
