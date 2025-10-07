using './volume.bicep'

// Image info

// Deployment info
param location='westeurope'
param ccePolicies={
  volume: ''
}
param managedIDName='cacidashboard'

param shareName=''
param storageAccountName=''
param key=''
