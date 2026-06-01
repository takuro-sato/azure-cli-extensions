using './volume.bicep'

// Image info
param registry=''
param repository=''
param tag=''

// Deployment info
param location='westeurope'
param ccePolicies={
  volume: ''
}
param managedIDName=''

param useVnet=true

param storageAccountName=''
param shareName='testshare'
