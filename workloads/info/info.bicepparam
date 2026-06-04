using './info.bicep'

// Image info
param registry=''
param repository=''
param tag=''

// Deployment info
param location=''
param zone=''
param useVnet=false
param ccePolicies={
  info: ''
}

param requireHostAmdCert=true
param expectUvmSignature='Prod'
