#Requires -Version 5.1
###############################################################################
# Lab 06 - Node Taint / Scheduling Issue (PowerShell)
###############################################################################

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

# ── Deploy ──────────────────────────────────────────────────────────────────
function Deploy-Lab {
    New-AksLabCluster -Scenario 'taint'

    Write-Header 'Injecting Lab Scenario'

    Write-Log 'Applying maintenance taints to all nodes...'
    $nodes = kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>$null
    foreach ($node in $nodes.Split(' ')) {
        kubectl taint nodes $node maintenance=scheduled:NoSchedule --overwrite 2>$null
    }
    Write-Ok 'Taints applied to all nodes'

    Write-Log 'Creating deployment...'
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

    Start-Sleep -Seconds 8
    Write-Host ''
    Write-Separator
    Write-Err 'All pods are Pending - no node will accept them!'
    kubectl get pods -l app=web-app --no-headers 2>$null
    Write-Info 'Investigate why pods cannot be scheduled.'
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
        Write-Info 'Hint 2: Check the taints on the cluster nodes.'
        Write-Info '  kubectl describe node <name> | Select-String -Context 0,3 Taints'
    } else {
        Write-Info "Hint 3: Remove the taint: kubectl taint nodes --all maintenance=scheduled:NoSchedule-"
    }
}

# ── Solution ────────────────────────────────────────────────────────────────
function Show-LabSolution {
    Write-Header 'Solution'
    Write-Info 'Remove the taint from all nodes:'
    Write-Host '  kubectl taint nodes --all maintenance=scheduled:NoSchedule-' -ForegroundColor Cyan
    Write-Host ''
    Write-Info 'Or add a toleration to the deployment for the maintenance taint.'
}

# ── Run ─────────────────────────────────────────────────────────────────────
$desc = @"
  Scenario
  The ops team applied maintenance taints to all nodes but forgot
  to remove them. web-app pods are stuck in Pending.

  Objective
  Fix the scheduling issue so all 3 replicas are Running.

  Useful commands
    kubectl get pods
    kubectl describe pod <name>
    kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
"@

Start-Lab -Name 'node-taint' -Title 'Lab 06 - Node Taint / Scheduling Issue' `
    -Description $desc `
    -DeployFn   { Deploy-Lab } `
    -ValidateFn { Test-LabFix } `
    -HintFn     { param($a) Get-LabHint $a } `
    -SolutionFn { Show-LabSolution }
