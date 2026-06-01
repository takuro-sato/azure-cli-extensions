using './stress-test-v2-cplat-vm-nonconf.bicep'

// Image info
param registry=''
param repository=''
param tag='latest'

// Deployment info
param location=''
param vmSku=''
param cplatBlob=''
param storageAccountName=''
param storageAccountKey=''
param storageAccountFqdn=''
param shareName=''
