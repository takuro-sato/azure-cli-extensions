using './ccf_verify_uvm.bicep'

// Image info
param registry=''
param repository=''
param tag=''

// Deployment info
param location=''
param ccePolicies={
  ccf_verify_uvm: ''
}
