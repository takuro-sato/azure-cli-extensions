#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$HelmChartDir = '',
    [string]$GitUrl = 'https://github.com/azure-core-compute/VirtualNodesOnACI-1P',
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$AksClusterName,

    [Parameter(Mandatory = $false, Position = 2)]
    [string]$Namespace = 'default',

    [Parameter(Mandatory = $false, HelpMessage = 'Git branch to use. Default: preview/windows.')]
    [string]$GitBranch = 'preview/windows',

    [Parameter(Mandatory = $false, HelpMessage = 'Whether to deploy the Windows VN2 replica (sets replicaCountWindows=1). Default: False.')]
    [bool]$InstallWindows = $false
)

$ErrorActionPreference = 'Stop'


# Prompt for GitBranch when not supplied on the command line.
# Pressing Enter (empty input) defaults to preview/windows.
if (-not $PSBoundParameters.ContainsKey('GitBranch')) {
    $answer = Read-Host "Enter Git branch to use (default: preview/windows)"
    if (-not [string]::IsNullOrEmpty($answer)) {
        $GitBranch = $answer
    }
}

# Prompt for InstallWindows when not supplied on the command line.
# Pressing Enter (empty input) defaults to $false.
if (-not $PSBoundParameters.ContainsKey('InstallWindows')) {
    $answer = Read-Host "Install Windows VN2 replica? [y/n]"
    $InstallWindows = $answer -match '^(y|yes|true|1)$'
}

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

. (Join-Path $PSScriptRoot 'isolate_kube_config.inc.ps1')

# Set the AKS context for kubectl
Write-Host "Setting the AKS context for kubectl..."
az aks get-credentials --overwrite-existing --resource-group $ResourceGroup --name $AksClusterName

# Switch to the specified namespace
kubectl config set-context --current --namespace=$Namespace

# Check if vn2 is already installed and install if not
$vn2Installed = (helm list --filter 'vn2' | Select-String -Pattern 'vn2' -Quiet)
if ($vn2Installed) {
    Write-Host "Helm release 'vn2' is already installed. Skipping Helm install."
} else {
    Write-Host "Helm release 'vn2' is not installed. Proceeding with installation."

    if (-not [string]::IsNullOrEmpty($HelmChartDir)) {
        # Use a caller-provided chart directory
        $ChartPath = $HelmChartDir
        Write-Host "Using provided Helm chart directory: $ChartPath"
    } else {
        if (-not (Test-Path 'VirtualNodesOnACI-1P/Helm')) {
            Write-Host "Cloning $GitUrl (branch $GitBranch)..."
            git clone $GitUrl --depth 1 --single-branch --branch $GitBranch VirtualNodesOnACI-1P
        }
        $ChartPath = 'VirtualNodesOnACI-1P/Helm'
    }

    # Install a virtual node
    $McResourceGroup = az aks show --resource-group $ResourceGroup --name $AksClusterName --query 'nodeResourceGroup' -o tsv
    Write-Host "Installing VN2, vnetResourceGroupName=$McResourceGroup"
    $HelmSetArgs = @(
        '--set', 'replicaCount=1'
        '--set', "vnetResourceGroupName=$McResourceGroup"
    )
    if ($InstallWindows) {
        $HelmSetArgs += @('--set', 'replicaCountWindows=1')
    }

    helm install vn2 $ChartPath @HelmSetArgs
}
