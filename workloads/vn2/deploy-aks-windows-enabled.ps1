#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ClusterName,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$Location,

    [Parameter(Mandatory = $false, Position = 3, HelpMessage = 'Whether to add a Windows node pool to the AKS cluster (default: True).')]
    [bool]$AddWindowsNodePool = $true,

    [Parameter(Mandatory = $false, HelpMessage = 'Azure subscription used for the AKS cluster (default: "ACI Development").')]
    [string]$AKSSubscription = 'ACI Development',

    [Parameter(Mandatory = $false, HelpMessage = 'Subscription ID for the Confidential Testing managed identity scope (default: 824db9f9-0ff1-49f2-ab3e-4b72dfb9dd6a).')]
    [string]$ConfidentialTestingSubscriptionId = '824db9f9-0ff1-49f2-ab3e-4b72dfb9dd6a'
)

az account set --subscription $AKSSubscription

$ErrorActionPreference = 'Stop'
# Resolve the real Azure CLI executable up-front so the wrapper below can invoke
# it without recursing into itself.
$script:AzExe = (Get-Command az -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $script:AzExe) { Write-Error "Azure CLI ('az') was not found on PATH."; exit 1 }

function az {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $script:AzExe @args
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

# Variables (you can customize these)
$NodeCount         = 1                      # Number of nodes
$SubnetName        = 'cg'                   # Subnet name
$SubnetPrefix      = '10.225.0.0/24'        # Address range for the new subnet (starting from 10.225.0.0)
$AksIdentitySuffix = 'agentpool'            # Expected suffix of the AKS managed identity
$Role              = 'Contributor'          # Role to assign
$NodeVmSizesToTry  = @(
    'harvest_e4s_v3'
    'Standard_DC4as_cc_v6'
    'Standard_DC2as_cc_v6'
    'Standard_DC4as_cc_v5'
    'Standard_DC2as_cc_v5'
    'Standard_DC8as_cc_v6'
    'Standard_DC8as_cc_v5'

    'Standard_EC4as_cc_v6'
    'Standard_EC2as_cc_v6'
    'Standard_EC4as_cc_v5'
    'Standard_EC2as_cc_v5'
    'Standard_EC8as_cc_v6'
    'Standard_EC8as_cc_v5'

    'Standard_D4as_v5'
    'Standard_D4as_v6'
    'Standard_D2as_v5'
    'Standard_D2as_v6'
    'Standard_D4s_v5'
    'Standard_D4s_v6'
    'Standard_D2s_v5'
    'Standard_D2s_v6'

    'Standard_E4s_v5'
    'Standard_E4s_v6'
    'Standard_E2s_v5'
    'Standard_E2s_v6'
)
$MinCount = 1                       # Minimum number of nodes (for autoscaler, Dev/Test)
$MaxCount = 3                       # Maximum number of nodes (for autoscaler, Dev/Test)

# Windows node pool settings
$WindowsNodepoolName = 'npwin'     # Windows node pool name (max 6 chars)
$WindowsNodeVmSize = if ($env:WINDOWS_NODE_VM_SIZE) { $env:WINDOWS_NODE_VM_SIZE } else { 'harvest_e4s_v3' }
$WindowsAdminUsername = 'azureuser'
# Generate a compliant random password unless one is provided via env
if ($env:WINDOWS_ADMIN_PASSWORD) {
    $WindowsAdminPassword = $env:WINDOWS_ADMIN_PASSWORD
} else {
    $randomBytes = New-Object 'System.Byte[]' 18
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($randomBytes)
    $WindowsAdminPassword = [System.Convert]::ToBase64String($randomBytes) + 'Aa1!'
}

# Extra args for `az aks create`; Windows node pools require Azure CNI and Windows admin credentials
$ExtraAksCreateArgs = @(
    '--network-plugin', 'azure'
    '--windows-admin-username', $WindowsAdminUsername
    '--windows-admin-password', $WindowsAdminPassword
)


. (Join-Path $PSScriptRoot 'isolate_kube_config.inc.ps1')

# 1) Check and Create Resource Group if it doesn't exist
az group show --name $ResourceGroup 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Resource group '$ResourceGroup' already exists. Moving to the next step..."
} else {
    Write-Host "Creating resource group '$ResourceGroup' in '$Location'..."
    az group create --name $ResourceGroup --location $Location
}

# 2) Check if AKS Cluster exists and create if it doesn't
$null = az aks show --resource-group $ResourceGroup --name $ClusterName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "AKS cluster '$ClusterName' already exists in resource group '$ResourceGroup'. Skipping creation."
} else {
    $success = $false
    foreach ($vmSku in $NodeVmSizesToTry) {
        Write-Host "Creating AKS cluster with $vmSku..."
        az aks create `
            --resource-group $ResourceGroup `
            --name $ClusterName `
            --node-count $NodeCount `
            --node-vm-size $vmSku `
            --generate-ssh-keys `
            --location $Location `
            --enable-managed-identity `
            --enable-cluster-autoscaler `
            --min-count $MinCount `
            --max-count $MaxCount `
            --auto-upgrade-channel patch `
            --node-os-upgrade-channel NodeImage `
            --nodepool-name 'vn2np' `
            --nodepool-labels 'environment=devtest' `
            --os-sku AzureLinux `
            @ExtraAksCreateArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host "AKS cluster '$ClusterName' created successfully with $vmSku."
            $success = $true
            break
        } else {
            Write-Host "Failed to create AKS cluster with $vmSku. Trying next VM size..."
        }
    }
    if (-not $success) {
        Write-Error "Error: Failed to create AKS cluster with all tried VM sizes."
        exit 1
    }
}

# wait until the resource group can be queried
Start-Sleep -Seconds 5

# Get the resource group name of the managed cluster (MC_* is the default resource group for AKS managed resources)
$McResourceGroup = az aks show --resource-group $ResourceGroup --name $ClusterName --query 'nodeResourceGroup' -o tsv
Write-Host "Managed Cluster Resource Group: $McResourceGroup"

# 3) Retrieve the VNet details
$VnetName = az network vnet list --resource-group $McResourceGroup --query '[0].name' -o tsv
$VnetId   = az network vnet show --resource-group $McResourceGroup --name $VnetName --query 'id' -o tsv
Write-Host "Virtual Network: $VnetName"

# 4) Create a Subnet within the VNet
az network vnet subnet show --resource-group $McResourceGroup --vnet-name $VnetName --name $SubnetName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Subnet '$SubnetName' already exists in VNet '$VnetName'. Skipping creation."
} else {
    Write-Host "Creating subnet '$SubnetName' in VNet '$VnetName'..."
    az network vnet subnet create `
        --resource-group $McResourceGroup `
        --vnet-name $VnetName `
        --name $SubnetName `
        --address-prefixes $SubnetPrefix `
        --delegations 'Microsoft.ContainerInstance/containerGroups'
}

# 4b) Add a Windows node pool (required to host VN2 Windows infrastructure pods)
if (-not $AddWindowsNodePool) {
    Write-Host "Skipping Windows node pool creation (AddWindowsNodePool = False)."
} else {
    az aks nodepool show --resource-group $ResourceGroup --cluster-name $ClusterName --name $WindowsNodepoolName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Windows node pool '$WindowsNodepoolName' already exists. Skipping creation."
    } else {
        Write-Host "Adding Windows node pool '$WindowsNodepoolName'..."
        az aks nodepool add `
            --resource-group $ResourceGroup `
            --cluster-name $ClusterName `
            --name $WindowsNodepoolName `
            --os-type Windows `
            --os-sku Windows2022 `
            --node-count 1 `
            --node-vm-size $WindowsNodeVmSize
    }
}

# 5) Assign Contributor Role to AKS Managed Identity on MC Resource Group
# Find the managed identity (this identity will typically have a name that ends with "agentpool")
Write-Host "Fetching AKS Managed Identity..."
$AksManagedIdentityClientId = az identity list --resource-group $McResourceGroup --query "[?contains(name, '$AksIdentitySuffix')].clientId" -o tsv
if ([string]::IsNullOrEmpty($AksManagedIdentityClientId)) {
    Write-Error "Error: Managed Identity not found. Please check the AKS cluster and try again."
    exit 1
}

# Note: `az role assignment create` is idempotent, so we don't check if the role assignment already exists

$SubscriptionId = az account show --query id -o tsv

# Assign Contributor role on the AKS resource group
$Scope = "/subscriptions/$SubscriptionId/resourceGroups/$McResourceGroup"
Write-Host "Assigning 'Contributor' role to Managed Identity '$AksManagedIdentityClientId' on '$McResourceGroup'..."
az role assignment create `
    --assignee $AksManagedIdentityClientId `
    --role $Role `
    --scope $Scope


Write-Host "Getting AKS credentials..."
Write-Host "az aks get-credentials --overwrite-existing --resource-group $ResourceGroup --name $ClusterName"
az aks get-credentials --overwrite-existing --resource-group $ResourceGroup --name $ClusterName
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get AKS credentials."
    exit 1
}

Write-Host "AKS cluster deployment and subnet configuration completed."

az account set --subscription "Confidential Testing"

$RunnerIdentityResourceGroup = 'c-aci-dashboard'
$RunnerIdentityName          = 'cacidashboard'

$RunnerClientId = az identity show --resource-group $RunnerIdentityResourceGroup -n $RunnerIdentityName --query 'clientId' -o tsv

$RegionalIdentityName = "$RunnerIdentityName-$Location"
# $RegionalIdentityClientId = az identity show --resource-group $RunnerIdentityResourceGroup -n $RegionalIdentityName --query 'clientId' -o tsv

# Allow runner access to the AKS itself
$Scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
Write-Host "Assigning 'Contributor' role to Managed Identity '$RunnerClientId' on '$ResourceGroup'..."
az role assignment create `
    --assignee $RunnerClientId `
    --role $Role `
    --scope $Scope
# ...as well as the MC resource group
$Scope = "/subscriptions/$SubscriptionId/resourceGroups/$McResourceGroup"
Write-Host "Assigning 'Contributor' role to Managed Identity '$RunnerClientId' on '$McResourceGroup'..."
az role assignment create `
    --assignee $RunnerClientId `
    --role $Role `
    --scope $Scope

# Allow the AKS identity to have Managed Identity Operator on the cacidashboard-${region} identity so that we can test VN2 managed identity containers
$Scope = "/subscriptions/$ConfidentialTestingSubscriptionId/resourceGroups/$RunnerIdentityResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$RegionalIdentityName"
Write-Host "Assigning 'Managed Identity Operator' role to Managed Identity '$AksManagedIdentityClientId' on '$RegionalIdentityName'..."
az role assignment create `
    --assignee $AksManagedIdentityClientId `
    --role 'Managed Identity Operator' `
    --scope $Scope

az account set --subscription $AKSSubscription
