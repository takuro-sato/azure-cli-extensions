using './skr.bicep'

// Image info
param registry=''
param tag=''

// Deployment info
param location=''
param ccePolicies={
  skr: ''
}
param managedIDName=''
