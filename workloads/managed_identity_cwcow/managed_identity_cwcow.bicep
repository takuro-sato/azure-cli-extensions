// Confidential WCOW equivalent of workloads/managed_identity.
//
// A single confidential Windows container with a user-assigned managed identity
// that probes IMDS for an OAuth2 token. ACI Windows groups can't mount volumes
// or run multiple containers, but the IMDS endpoint is reachable the same way as
// Linux, so this is a faithful Windows port: no vnet, no registry creds (the
// servercore image is pulled from mcr), just the identity + an IMDS probe.
//
// Uses Windows Server Core (ships curl.exe + full PowerShell) rather than
// nanoserver (which has neither).
param location string
param tag string
param ccePolicies object
param managedIDGroup string = resourceGroup().name
param managedIDName string

param cpu int = 4
param memoryInGb int = 8

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)}': {}
    }
  }
  properties: {
    osType: 'Windows'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.managed_identity_cwcow
    }
    containers: [
      {
        name: 'primary'
        properties: {
          // Pin by digest by default: the c-aci-testing VM harness resolves tag
          // refs via `oras manifest fetch --platform linux/amd64`, which has no
          // match in the Windows servercore manifest list and fails. Pass a
          // non-empty `tag` to opt into tag resolution.
          image: empty(tag) ? 'mcr.microsoft.com/windows/servercore@sha256:b066ad35b01f928ef9ea7d8551e3bd8835749e7479e107beaa2655bebbcb6408' : 'mcr.microsoft.com/windows/servercore:${tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          command: [
            'powershell.exe'
            '-Command'
            '''
            $ErrorActionPreference = 'SilentlyContinue'
            Write-Output 'Testing managed identity...'
            $tries = 0
            $success = $false
            while ($tries -lt 5) {
              $tries++
              # Important: do not expose the token to stdout — the container log
              # is fetched and displayed by the pipeline.
              curl.exe --fail -s -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" -o "$env:TEMP\token.json"
              if ($LASTEXITCODE -eq 0) { $success = $true; break }
              Write-Output "Attempt $tries failed, retrying..."
              Start-Sleep -Seconds 5
            }
            if (-not $success) {
              Write-Output ('ERROR: Failed to retrieve token from IMDS after ' + $tries + ' attempts')
              Write-Output ('OUTPUT: {"attempts": ' + $tries + ', "success": false}')
              Start-Sleep -Seconds 2147483
            }
            Write-Output 'IMDS request successful'
            Write-Output ('OUTPUT: {"attempts": ' + $tries + ', "success": true}')
            Start-Sleep -Seconds 2147483
            '''
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
