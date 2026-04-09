#Requires -Version 5.1
###############################################################################
# Lab 07 - NSG Blocking Inbound Traffic (PowerShell)
###############################################################################

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

$script:NsgName      = ''
$script:DenyRuleName = 'DenyInbound80'

# ── Deploy ──────────────────────────────────────────────────────────────────
function Deploy-Lab {
    New-AksLabCluster -Scenario 'nsg'

    Write-Header 'Injecting Lab Scenario'

    Write-Log 'Deploying web application with LoadBalancer...'
    @'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
'@ | kubectl apply -f -
    Write-Ok 'Deployment + LoadBalancer service created'

    Write-Log 'Waiting for external IP (may take 1-2 minutes)...'
    $extIp = ''
    for ($i = 0; $i -lt 30; $i++) {
        $extIp = kubectl get svc web-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        if ($extIp -and $extIp -ne 'null') { break }
        Start-Sleep -Seconds 10
    }
    if (-not $extIp -or $extIp -eq 'null') {
        Write-Err 'Could not get external IP. Lab setup incomplete.'
        return
    }
    Write-Ok "External IP: $extIp"

    Write-Log 'Configuring NSG deny rule...'
    $script:NsgName = az network nsg list -g $script:McResourceGroup --query '[0].name' -o tsv 2>$null
    if (-not $script:NsgName) {
        Write-Err 'Could not find NSG. Lab setup incomplete.'
        return
    }

    az network nsg rule create `
        --resource-group $script:McResourceGroup `
        --nsg-name $script:NsgName `
        --name $script:DenyRuleName `
        --priority 100 `
        --direction Inbound `
        --access Deny `
        --protocol Tcp `
        --destination-port-ranges 80 `
        --source-address-prefixes '*' `
        --destination-address-prefixes '*' `
        -o none 2>$null
    Write-Ok 'NSG deny rule added'

    Write-Host ''
    Write-Separator
    Write-Err 'External traffic to port 80 is BLOCKED!'
    Write-Info "External IP       : $extIp"
    Write-Info "MC Resource Group : $($script:McResourceGroup)"
    Write-Info "NSG Name          : $($script:NsgName)"
    Write-Host ''
    Write-Info 'Pods are running and the service has an IP, but HTTP requests time out.'
    Write-Info 'The problem is at the Azure networking level.'
}

# ── Validate ────────────────────────────────────────────────────────────────
function Test-LabFix {
    $ruleCheck = az network nsg rule show `
        --resource-group $script:McResourceGroup `
        --nsg-name $script:NsgName `
        --name $script:DenyRuleName 2>&1

    if ($ruleCheck -match 'ResourceNotFound|not found|could not be found') {
        Write-Ok 'NSG deny rule has been removed!'
        $extIp = kubectl get svc web-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        if ($extIp) { Write-Ok "Service should be reachable at http://$extIp" }
        return $true
    }
    Write-Err "The deny NSG rule '$($script:DenyRuleName)' still exists."
    Write-Info "NSG: $($script:NsgName) in RG: $($script:McResourceGroup)"
    return $false
}

# ── Hint ────────────────────────────────────────────────────────────────────
function Get-LabHint([int]$Attempt) {
    Write-Host ''
    if ($Attempt -lt 2) {
        Write-Info 'Hint 1: The issue is at Azure networking level, not Kubernetes.'
        Write-Info '  Look at Network Security Groups (NSG).'
    } elseif ($Attempt -lt 4) {
        Write-Info 'Hint 2: List NSG rules in the MC_ resource group:'
        Write-Info "  az network nsg rule list --nsg-name $($script:NsgName) -g $($script:McResourceGroup) -o table"
    } else {
        Write-Info "Hint 3: Delete the deny rule '$($script:DenyRuleName)':"
        Write-Info "  az network nsg rule delete --nsg-name $($script:NsgName) -g $($script:McResourceGroup) -n $($script:DenyRuleName)"
    }
}

# ── Solution ────────────────────────────────────────────────────────────────
function Show-LabSolution {
    Write-Header 'Solution'
    Write-Info 'Delete the NSG deny rule:'
    Write-Host "  az network nsg rule delete --resource-group $($script:McResourceGroup) --nsg-name $($script:NsgName) --name $($script:DenyRuleName)" -ForegroundColor Cyan
    Write-Host ''
    Write-Info "NSG rule '$($script:DenyRuleName)' (priority 100) blocks all inbound TCP/80."
    Write-Info 'Deleting it restores external access to the LoadBalancer.'
}

# ── Run ─────────────────────────────────────────────────────────────────────
$desc = @"
  Scenario
  A web-app has a LoadBalancer service with an external IP, but
  HTTP requests on port 80 time out. The issue is at the Azure
  networking level.

  Objective
  Fix the networking issue so the service is externally reachable on port 80.

  Useful commands
    kubectl get svc web-svc
    az network nsg list -g <MC_resource_group> -o table
    az network nsg rule list --nsg-name <nsg> -g <MC_resource_group> -o table
"@

Start-Lab -Name 'nsg-blocking' -Title 'Lab 07 - NSG Blocking Inbound Traffic' `
    -Description $desc `
    -DeployFn   { Deploy-Lab } `
    -ValidateFn { Test-LabFix } `
    -HintFn     { param($a) Get-LabHint $a } `
    -SolutionFn { Show-LabSolution }
