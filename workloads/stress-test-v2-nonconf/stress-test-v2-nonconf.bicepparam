using './stress-test-v2-nonconf.bicep'

// Image info
param registry=''
param repository=''
param tag='latest'

// Deployment info
param location=''
param managedIDName=''
param shareName=''
