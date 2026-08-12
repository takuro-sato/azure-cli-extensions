using './non_confidential_cwcow.bicep'

// Image info
param registry=''
param repository=''
param tag=''

// Deployment info
param location=''
param zone=''
param useVnet=false
param managedIDName=''
