using './long_lived_maa_tester.bicep'

// Image info
param registry=''
param repository=''
param tag=''

// Deployment info
param location=''
param ccePolicies={
  long_lived_maa_tester: ''
}
param managedIDName=''
