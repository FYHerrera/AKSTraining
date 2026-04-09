#Requires -Version 5.1
###############################################################################
# Lab 02 - Pod Stuck in Pending (PowerShell)
###############################################################################

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

# ── Deploy ──────────────────────────────────────────────────────────────────
function Deploy-Lab {
    New-AksLabCluster -Scenario 'pending'

    Write-Header 'Injecting Lab Scenario'

    Write-Log 'Creating deployment with scheduling issue...'
    @'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      nodeSelector:
        disktype: ssd
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
'@ | kubectl apply -f -
    Write-Ok "Deployment 'web-app' created"

    Start-Sleep -Seconds 5

    Write-Host ''
    Write-Separator
    Write-Err 'All pods are stuck in Pending state!'
    kubectl get pods -l app=web-app --no-headers 2>$null
    Write-Info 'Investigate why the pods cannot be scheduled.'
}

# ── Validate ────────────────────────────────────────────────────────────────
function Test-LabFix {
    $running = (kubectl get pods -l app=web-app --no-headers 2>$null | Select-String 'Running' | Measure-Object).Count
    if ($running -ge 3) {
        Write-Ok 'All 3 replicas are Running!'
        return $true
    }
    Write-Err "Only $running/3 replicas are Running."
    kubectl get pods -l app=web-app --no-headers 2>$null
    return $false
}

# ── Hint ────────────────────────────────────────────────────────────────────
function Get-LabHint([int]$Attempt) {
    Write-Host ''
    if ($Attempt -lt 2) {
        Write-Info 'Hint 1: Describe a pending pod and read the Events section.'
    } elseif ($Attempt -lt 4) {
        Write-Info 'Hint 2: Check the nodeSelector and compare with node labels.'
        Write-Info '  kubectl get nodes --show-labels'
    } else {
        Write-Info "Hint 3: nodeSelector requires 'disktype=ssd' but no node has it."
        Write-Info '  Label nodes: kubectl label nodes --all disktype=ssd'
        Write-Info '  Or remove the nodeSelector from the deployment.'
    }
}

# ── Solution ────────────────────────────────────────────────────────────────
function Show-LabSolution {
    Write-Header 'Solution'
    Write-Info 'Option A - Label the nodes:'
    Write-Host '  kubectl label nodes --all disktype=ssd' -ForegroundColor Cyan
    Write-Host ''
    Write-Info 'Option B - Remove nodeSelector from deployment:'
    Write-Host "  kubectl patch deployment web-app --type=json -p='[{`"op`":`"remove`",`"path`":`"/spec/template/spec/nodeSelector`"}]'" -ForegroundColor Cyan
}

# ── Run ─────────────────────────────────────────────────────────────────────
$desc = @"
  Scenario
  A developer created a Deployment called web-app with 3 replicas,
  but all pods are stuck in Pending. The cluster has available
  resources, but something prevents scheduling.

  Objective
  Make all 3 pods of the web-app deployment reach Running state.

  Useful commands
    kubectl get pods
    kubectl describe pod <name>
    kubectl get nodes --show-labels
"@

Start-Lab -Name 'pod-pending' -Title 'Lab 02 - Pod Stuck in Pending' `
    -Description $desc `
    -DeployFn   { Deploy-Lab } `
    -ValidateFn { Test-LabFix } `
    -HintFn     { param($a) Get-LabHint $a } `
    -SolutionFn { Show-LabSolution }
