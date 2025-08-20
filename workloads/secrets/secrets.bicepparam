using './secrets.bicep'

// Image info
param tag=''

// Deployment info
param location=''
param ccePolicies={
  secrets: ''
}

param mysecret=''
