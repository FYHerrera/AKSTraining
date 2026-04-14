#Requires -Version 5.1
###############################################################################
# Common.ps1 - Shared library for AKS Lab scripts (PowerShell)
#
# Dot-source this at the top of every lab script:
#   . "$PSScriptRoot\lib\Common.ps1"
###############################################################################

$ErrorActionPreference = 'Stop'

# ── Defaults ─────────────────────────────────────────────────────────────────
$script:DefaultRegion    = if ($env:AKS_LAB_REGION)     { $env:AKS_LAB_REGION }     else { 'canadacentral' }
$script:DefaultNodeCount = if ($env:AKS_LAB_NODE_COUNT) { $env:AKS_LAB_NODE_COUNT } else { 1 }
$script:DefaultVmSize    = if ($env:AKS_LAB_VM_SIZE)    { $env:AKS_LAB_VM_SIZE }    else { 'Standard_D8ds_v5' }
$script:K8sVersion       = ''

# ── State ────────────────────────────────────────────────────────────────────
$script:LogFile          = ''
$script:ResourceGroup    = ''
$script:ClusterName      = ''
$script:McResourceGroup  = ''
$script:LabStartTime     = $null

# ── Logging ──────────────────────────────────────────────────────────────────
function Write-LogFile([string]$Message) {
    if ($script:LogFile) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $script:LogFile -Value "[$ts] $Message"
    }
}

function Write-Log([string]$Message) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] $Message"
    Write-LogFile $Message
}
function Write-Ok([string]$Message) {
    Write-Host "  [OK] $Message" -ForegroundColor Green
    Write-LogFile "[OK] $Message"
}
function Write-Err([string]$Message) {
    Write-Host "  [X] $Message" -ForegroundColor Red
    Write-LogFile "[ERROR] $Message"
}
function Write-Warn([string]$Message) {
    Write-Host "  [!] $Message" -ForegroundColor Yellow
    Write-LogFile "[WARN] $Message"
}
function Write-Info([string]$Message) {
    Write-Host "  [i] $Message" -ForegroundColor Cyan
    Write-LogFile "[INFO] $Message"
}

function Write-Header([string]$Title) {
    Write-Host ''
    Write-Host "  =======================================================" -ForegroundColor Blue
    Write-Host "    $Title" -ForegroundColor Blue
    Write-Host "  =======================================================" -ForegroundColor Blue
    Write-Host ''
}

function Write-Separator {
    Write-Host "  -------------------------------------------------------" -ForegroundColor Blue
}

# ── Initialise logging ─────────────────────────────────────────────────────
function Initialize-Logging([string]$LabName) {
    $callerDir = Split-Path -Parent (Get-PSCallStack)[1].ScriptName
    $logDir    = Join-Path (Split-Path -Parent $callerDir) 'logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $logDir "${LabName}-${ts}.log"
    Write-LogFile "=== Lab session started: $LabName ==="
}

# ── Name generator ──────────────────────────────────────────────────────────
function New-LabName([string]$Scenario) {
    $suffix = -join ((97..122) + (48..57) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    return "aks-lab-${Scenario}-${suffix}"
}

# ── Pre-flight checks ──────────────────────────────────────────────────────
function Test-Prerequisites {
    Write-Header 'Pre-flight Checks'

    # Azure CLI
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Err 'Azure CLI (az) is not installed.'
        Write-Info 'Install: https://learn.microsoft.com/cli/azure/install-azure-cli'
        exit 1
    }
    $azVer = (az version --query '"azure-cli"' -o tsv 2>$null)
    Write-Ok "Azure CLI found ($azVer)"

    # kubectl
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Warn 'kubectl not found - installing via Azure CLI...'
        az aks install-cli 2>$null
    }
    if (Get-Command kubectl -ErrorAction SilentlyContinue) {
        Write-Ok 'kubectl found'
    } else {
        Write-Err 'kubectl could not be installed. Please install it manually.'
        exit 1
    }

    # Azure login
    $account = $null
    try { $account = az account show -o json 2>$null | ConvertFrom-Json } catch {}
    if (-not $account) {
        Write-Err 'Not logged into Azure.'
        Write-Info 'Run:  az login'
        Write-Info 'Then re-run this lab.'
        exit 1
    }

    Write-Ok "Logged in as: $($account.user.name)"
    Write-Ok "Subscription: $($account.name) ($($account.id))"

    # Required Azure resource providers
    $requiredProviders = @(
        'Microsoft.ContainerService',
        'Microsoft.Network',
        'Microsoft.Compute',
        'Microsoft.Storage',
        'Microsoft.ManagedIdentity',
        'Microsoft.OperationsManagement',
        'Microsoft.OperationalInsights'
    )

    $missingProviders = @()
    foreach ($provider in $requiredProviders) {
        $state = az provider show --namespace $provider --query 'registrationState' -o tsv 2>$null
        if ($state -eq 'Registered') {
            Write-Ok "$provider registered"
        } else {
            Write-Err "$provider NOT registered (state: $state)"
            $missingProviders += $provider
        }
    }

    if ($missingProviders.Count -gt 0) {
        Write-Host ''
        Write-Warn "$($missingProviders.Count) provider(s) need registration:"
        foreach ($p in $missingProviders) {
            Write-Host "    - $p" -ForegroundColor Yellow
        }
        Write-Host ''
        $regChoice = Read-Host '  Register all missing providers now? (y/n)'
        if ($regChoice -match '^[Yy]') {
            foreach ($p in $missingProviders) {
                Write-Log "Registering $p..."
                az provider register --namespace $p -o none
            }
            Write-Log 'Waiting for all providers to register (may take 2-5 min)...'
            foreach ($p in $missingProviders) {
                $waitCount = 0
                while ((az provider show --namespace $p --query 'registrationState' -o tsv 2>$null) -ne 'Registered') {
                    $waitCount++
                    if ($waitCount -ge 30) {
                        Write-Err "Timeout waiting for $p. Try again later."
                        exit 1
                    }
                    Start-Sleep -Seconds 10
                }
                Write-Ok "$p registered"
            }
        } else {
            Write-Err 'Cannot proceed without required providers.'
            Write-Info 'Register manually:'
            foreach ($p in $missingProviders) {
                Write-Host "  az provider register --namespace $p" -ForegroundColor Cyan
            }
            exit 1
        }
    }

    Write-Host ''
    Write-Info 'All pre-flight checks passed!'
    Write-Host ''
}

# ── Get latest K8s version ─────────────────────────────────────────────────
function Get-LatestK8sVersion([string]$Region = $script:DefaultRegion) {
    $ver = az aks get-versions --location $Region --query "values[?isDefault].version" -o tsv 2>$null
    if ($ver) { $script:K8sVersion = $ver }
    else {
        $script:K8sVersion = '1.29'
        Write-Warn "Could not detect latest K8s version; defaulting to $($script:K8sVersion)"
    }
}

# ── Create AKS cluster ─────────────────────────────────────────────────────
function New-AksLabCluster {
    param(
        [Parameter(Mandatory)][string]$Scenario,
        [string]$ExtraArgs = ''
    )

    $script:ClusterName   = New-LabName $Scenario
    $script:ResourceGroup = "$($script:ClusterName)-rg"

    Write-Header 'Creating Lab Environment'
    Write-Info "Resource Group : $($script:ResourceGroup)"
    Write-Info "Cluster Name   : $($script:ClusterName)"
    Write-Info "Region         : $($script:DefaultRegion)"
    Write-Info "Node Count     : $($script:DefaultNodeCount)"
    Write-Info "VM Size        : $($script:DefaultVmSize)"
    Write-Host ''

    Write-Log 'Creating resource group...'
    az group create --name $script:ResourceGroup --location $script:DefaultRegion -o none
    Write-Ok 'Resource group created'

    Get-LatestK8sVersion $script:DefaultRegion
    Write-Info "Kubernetes version: $($script:K8sVersion)"

    Write-Log 'Creating AKS cluster (this takes ~5-10 minutes)...'
    $cmd = "az aks create --resource-group $($script:ResourceGroup) --name $($script:ClusterName) " +
           "--node-count $($script:DefaultNodeCount) --node-vm-size $($script:DefaultVmSize) " +
           "--kubernetes-version $($script:K8sVersion) --location $($script:DefaultRegion) " +
           "--generate-ssh-keys --network-plugin azure -o none $ExtraArgs"
    Invoke-Expression $cmd
    Write-Ok 'AKS cluster created'

    Write-Log 'Fetching cluster credentials...'
    az aks get-credentials --resource-group $script:ResourceGroup --name $script:ClusterName --overwrite-existing
    Write-Ok "kubectl configured for $($script:ClusterName)"

    $script:McResourceGroup = az aks show -g $script:ResourceGroup -n $script:ClusterName `
        --query 'nodeResourceGroup' -o tsv 2>$null

    Test-ClusterHealth
}

# ── Verify cluster health ─────────────────────────────────────────────────
function Test-ClusterHealth {
    Write-Log 'Verifying cluster health...'

    kubectl wait --for=condition=Ready nodes --all --timeout=300s 2>$null | Out-Null
    $readyCount = (kubectl get nodes --no-headers 2>$null | Select-String ' Ready' | Measure-Object).Count
    Write-Ok "$readyCount/$($script:DefaultNodeCount) nodes Ready"

    $retries = 0
    while ($retries -lt 12) {
        $bad = (kubectl get pods -n kube-system --no-headers 2>$null |
            Select-String -NotMatch 'Running|Completed' | Measure-Object).Count
        if ($bad -eq 0) { break }
        $retries++
        Start-Sleep -Seconds 10
    }
    Write-Ok 'System pods healthy'
}

# ── Cleanup ────────────────────────────────────────────────────────────────
function Remove-LabResources {
    Write-Host ''
    Write-Separator
    $response = Read-Host '  Delete all lab resources? (y/n)'
    if ($response -match '^[Yy]') {
        Write-Log "Deleting resource group $($script:ResourceGroup) (background)..."
        az group delete --name $script:ResourceGroup --yes --no-wait 2>$null
        Write-Ok 'Deletion initiated - may take a few minutes in the background.'
    } else {
        Write-Warn 'Resources kept.'
        Write-Warn "Resource Group : $($script:ResourceGroup)"
        Write-Warn "Delete later   : az group delete --name $($script:ResourceGroup) --yes"
    }
}

# ── Interactive menu ───────────────────────────────────────────────────────
function Start-LabMenu {
    param(
        [Parameter(Mandatory)][scriptblock]$ValidateFn,
        [Parameter(Mandatory)][scriptblock]$HintFn,
        [Parameter(Mandatory)][scriptblock]$SolutionFn
    )
    $attempt = 0

    while ($true) {
        Write-Host ''
        Write-Separator
        Write-Host '  Lab Menu' -ForegroundColor White
        Write-Separator
        Write-Host '    [V]  Validate my fix'   -ForegroundColor Green
        Write-Host '    [H]  Request a hint'    -ForegroundColor Yellow
        Write-Host '    [S]  Show solution'     -ForegroundColor Cyan
        Write-Host '    [Q]  Quit & Cleanup'    -ForegroundColor Red
        Write-Host ''
        $choice = Read-Host '  Choose an option'
        Write-LogFile "Menu choice: '$choice' (attempt=$attempt)"

        switch ($choice.ToLower()) {
            { $_ -in 'v','validate' } {
                $attempt++
                Write-Info "Validation attempt #$attempt"
                $result = & $ValidateFn
                if ($result) {
                    Write-Header 'Lab Completed Successfully!'
                    $elapsed = (Get-Date) - $script:LabStartTime
                    $mins = [int]$elapsed.TotalMinutes
                    $secs = $elapsed.Seconds
                    Write-Ok "Time: ${mins}m ${secs}s  |  Attempts: $attempt"
                    Write-LogFile "LAB COMPLETED: ${mins}m ${secs}s, $attempt attempts"
                    Remove-LabResources
                    return
                }
            }
            { $_ -in 'h','hint' } {
                & $HintFn $attempt
            }
            { $_ -in 's','solution' } {
                Write-Host ''
                $confirm = Read-Host '  Show the full solution? (y/n)'
                if ($confirm -match '^[Yy]') {
                    & $SolutionFn
                    Write-LogFile "User viewed solution at attempt $attempt"
                }
            }
            { $_ -in 'q','quit' } {
                Remove-LabResources
                return
            }
            default { Write-Warn 'Invalid choice. Use V, H, S or Q.' }
        }
    }
}

# ── Main lab runner ────────────────────────────────────────────────────────
function Start-Lab {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$DeployFn,
        [Parameter(Mandatory)][scriptblock]$ValidateFn,
        [Parameter(Mandatory)][scriptblock]$HintFn,
        [Parameter(Mandatory)][scriptblock]$SolutionFn
    )

    $script:LabStartTime = Get-Date
    Initialize-Logging $Name

    Write-Header $Title
    Write-Host $Description
    Write-Host ''

    Test-Prerequisites
    & $DeployFn

    Start-LabMenu -ValidateFn $ValidateFn -HintFn $HintFn -SolutionFn $SolutionFn
}
