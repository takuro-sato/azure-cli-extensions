using './skr_cwcow.bicep'

// Image info — the confidential Windows skr image lives in our ACR. tag is
// hard-coded (not param_set by `policies gen`, which we skip for fixed-policy
// workloads). allow_all does not bind to image layers, so 'latest' is safe.
param registry = 'cacidashboardaci.azurecr.io'
param tag = 'demo'

// Deployment info — location and managedIDName are populated at deploy time by
// c-aci-testing from the LOCATION / MANAGED_IDENTITY env vars.
param location = 'germanynorth'
param managedIDName = 'cacidashboard-germanynorth'

// Pre-populated permissive WCOW policy (api_version 0.11.0, mount_cims), loaded
// verbatim so its sha256 is the deployed SEV-SNP host_data. The key-release
// tests read the same file to bind their release policy. Matches the allow_all
// rego emitted by `c-aci-testing policies gen --policy-type allow_all` for an
// osType=Windows group (same content as workloads/info_cwcow).
param ccePolicies = {
  skr_cwcow: loadFileAsBase64('policy_skr_cwcow.rego')
}
