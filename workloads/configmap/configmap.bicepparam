using './configmap.bicep'

// Image info
param tag=''

// Deployment info
param location=''
param ccePolicies={
  configmap: ''
}

param myconfig=''
