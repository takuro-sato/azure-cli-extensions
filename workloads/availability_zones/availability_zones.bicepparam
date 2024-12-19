using './availability_zones.bicep'

// Image info
param tag=''

// Deployment info
param location=''
param ccePolicies={
  availability_zones: ''
}

param zone=''
