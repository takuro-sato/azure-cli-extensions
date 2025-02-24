using './virtualclient.bicep'

// Image info
param registry=''
param tag=''

// Deployment info
param location=''
param ccePolicies={
  virtualclient: ''
}
param managedIDName=''

param totalCpus=4
param totalMemoryGB=16

param profileName=''
