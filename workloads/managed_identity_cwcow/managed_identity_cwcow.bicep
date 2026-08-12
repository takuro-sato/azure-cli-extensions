// Confidential WCOW equivalent of workloads/managed_identity.
//
// A single confidential Windows container with a user-assigned managed identity
// that uses ACI's injected identity endpoint to request an OAuth2 token. ACI
// Windows groups can't mount volumes or run multiple containers, so this uses
// no vnet or registry credentials: the servercore image is pulled from MCR.
//
// Uses Windows Server Core (ships curl.exe + full PowerShell) rather than
// nanoserver (which has neither).
param location string
param tag string
param ccePolicies object
param managedIDGroup string = resourceGroup().name
param managedIDName string
param useVnet bool = false

param cpu int = 4
param memoryInGb int = 8

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: 'aci-long-lived-vnet-${location}'
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: virtualNetwork
  name: 'acisubnet'
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: managedIDName
  scope: resourceGroup(managedIDGroup)
}

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
    subnetIds: useVnet ? [{ id: subnet.id }] : []
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
          environmentVariables: [
            {
              name: 'MANAGED_IDENTITY_PRINCIPAL_ID'
              value: managedIdentity.properties.principalId
            }
          ]
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
              try {
                $null = Invoke-RestMethod -Uri $env:IDENTITY_ENDPOINT `
                  -Method Get `
                  -Headers @{ secret = $env:IDENTITY_HEADER } `
                  -Body @{ resource = 'https://storage.azure.com/'; principalId = $env:MANAGED_IDENTITY_PRINCIPAL_ID } `
                  -ContentType 'application/x-www-form-urlencoded' `
                  -TimeoutSec 10 `
                  -ErrorAction Stop
                $success = $true
                break
              } catch {
                $statusCode = 'unavailable'
                $responseBody = $_.ErrorDetails.Message
                if ($_.Exception.Response) {
                  $statusCode = [int]$_.Exception.Response.StatusCode
                  if ([string]::IsNullOrWhiteSpace($responseBody)) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    try {
                      $responseBody = $reader.ReadToEnd()
                    } finally {
                      $reader.Dispose()
                    }
                  }
                }
                if ([string]::IsNullOrWhiteSpace($responseBody)) {
                  $responseBody = $_.Exception.Message
                }
                Write-Output "Attempt $tries failed. HTTP status: $statusCode"
                Write-Output "Response: $responseBody"
              }
              if ($tries -lt 5) {
                Write-Output 'Retrying...'
                Start-Sleep -Seconds 5
              }
            }
            if (-not $success) {
              Write-Output ('ERROR: Failed to retrieve token from the identity endpoint after ' + $tries + ' attempts')
              Write-Output ('OUTPUT: {"attempts": ' + $tries + ', "success": false}')
              Start-Sleep -Seconds 2147483
            }
            Write-Output 'Identity endpoint request successful'
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
