using './skr-fixed-policy.bicep'

// Image info
param registry='cacidashboardaci.azurecr.io'
param tag='skr-fixed-policy'

// Deployment info
param location=''
param ccePolicies={
  skr_fixed_policy: loadFileAsBase64('policy_skr_fixed_policy.rego')
}
param managedIDName=''
