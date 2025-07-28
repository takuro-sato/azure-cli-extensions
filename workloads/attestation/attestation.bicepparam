using './attestation.bicep'

// Image info
param tag=''

// Deployment info
param location='westeurope'
param ccePolicies={
  attestation: ''
}
param attestationEndpoint=''
