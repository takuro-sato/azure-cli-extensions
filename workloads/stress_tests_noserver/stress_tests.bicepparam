using './stress_tests.bicep'

param script='workload_fio'

// Image info
param registry=''
param repository=''
param tag=''

// Deployment info
param location=''
param ccePolicies={
  stress_tests: ''
}
