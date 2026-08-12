using './non_confidential_wcow.bicep'

// Image info
param registry=''
param repository=''
param tag=''
param imageName='info-cwcow-ws2025'

// Deployment info
param location=''
param zone=''
param useVnet=false
param managedIDName=''
