// Confidential WCOW equivalent of workloads/vnet.
//
// Same ACI-service vnet path as the LCOW vnet workload: self-provisions a vnet
// + ACI-delegated subnet + NSG, then deploys a confidential container group
// injected into that subnet via `subnetIds` (no public IP). The only difference
// is osType 'Windows' and a Windows Server Core image running a PowerShell
// network check instead of the Linux `networking` image.
//
// This exercises confidential WINDOWS container-group subnet injection, which is
// only available on an ACISNP fleet whose unified cplat was installed with
// `-NetworkType byovnet` (e.g. australiacentral2). The CG itself is a normal ACI
// deployment — the fleet/cplat does the byovnet wiring, not this template.
//
// ACI Windows container groups are single-container only (multi-container is
// Linux-only), so this is one confidential Windows container with no public IP.
param location string
param ccePolicies object
param tag string = ''

param cpu int = 2
param memoryInGb int = 4

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Windows'
    sku: 'Confidential'
    subnetIds: [{ id: subnet.id }]
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.vnet_cwcow
    }
    containers: [
      {
        name: 'vnet-cwcow'
        properties: {
          // Pin the Server Core image by digest by default: the c-aci-testing VM
          // harness resolves tag refs via `oras manifest fetch --platform
          // linux/amd64`, which has no match in the Windows manifest list and
          // fails. A digest ref skips that resolution. Pass a non-empty `tag` to
          // opt into tag resolution. Server Core (not nanoserver) so that
          // powershell.exe + the Get-NetIPAddress / Test-NetConnection cmdlets
          // used by the network check are available.
          image: empty(tag) ? 'mcr.microsoft.com/windows/servercore@sha256:4566c6115c63ea3a3f15fd368d78dbf7a08064bb94d56428fab00eec033aea67' : 'mcr.microsoft.com/windows/servercore:${tag}'
          // No public IP (vnet-injected), so we assert from inside the
          // container: print the injected subnet IP (expected 10.0.0.x) and a
          // best-effort outbound connectivity probe, then idle so the platform
          // can scrape the log.
          command: [
            'powershell'
            '-Command'
            '''
            ipconfig /all
            $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '10.0.0.*' } | Select-Object -First 1).IPAddress
            Write-Output "VNET_CWCOW_SUBNET_IP=$ip"
            try {
              $r = Test-NetConnection -ComputerName mcr.microsoft.com -Port 443 -WarningAction SilentlyContinue
              Write-Output "VNET_CWCOW_OUTBOUND=$($r.TcpTestSucceeded)"
            } catch {
              Write-Output "VNET_CWCOW_OUTBOUND=error"
            }
            Write-Output "VNET_CWCOW_DONE"
            Start-Sleep -Seconds 120
            '''
          ]
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
        }
      }
    ]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: '${deployment().name}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 300
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: '${deployment().name}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: virtualNetwork
  name: '${deployment().name}-subnet'
  properties: {
    addressPrefix: '10.0.0.0/24'
    delegations: [
      {
        name: 'aciDelegation'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
    defaultOutboundAccess: false
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

output ids array = [containerGroup.id]
