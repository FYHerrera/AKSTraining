#Requires -Version 5.1
###############################################################################
# Lab 04 - ImagePullBackOff (PowerShell)
###############################################################################

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

# ── Deploy ──────────────────────────────────────────────────────────────────
function Deploy-Lab {
    New-AksLabCluster -Scenario 'imagepull'

    Write-Header 'Injecting Lab Scenario'

    Write-Log 'Creating deployment with bad image tag...'
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
        image: nginx:99.99.99
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
'@ | kubectl apply -f -
    Write-Ok "Deployment 'web-app' created"

    Start-Sleep -Seconds 15

    Write-Host ''
    Write-Separator
    Write-Err 'Pods are in ImagePullBackOff / ErrImagePull!'
    kubectl get pods -l app=web-app --no-headers 2>$null
    Write-Info 'Investigate why the image cannot be pulled.'
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
        Write-Info 'Hint 1: Describe a pod and check the Events for image errors.'
    } elseif ($Attempt -lt 4) {
        Write-Info 'Hint 2: Does the container image tag actually exist on Docker Hub?'
    } else {
        Write-Info "Hint 3: Tag 'nginx:99.99.99' does not exist. Use nginx:1.25."
        Write-Info '  kubectl set image deployment/web-app nginx=nginx:1.25'
    }
}

# ── Solution ────────────────────────────────────────────────────────────────
function Show-LabSolution {
    Write-Header 'Solution'
    Write-Info 'Set the image to a valid tag:'
    Write-Host '  kubectl set image deployment/web-app nginx=nginx:1.25' -ForegroundColor Cyan
    Write-Host ''
    Write-Info "The tag 'nginx:99.99.99' does not exist on Docker Hub."
}

# ── Run ─────────────────────────────────────────────────────────────────────
$desc = @"
  Scenario
  The dev team pushed a new deployment but made a typo in the image
  tag. All pods are stuck in ImagePullBackOff / ErrImagePull.

  Objective
  Fix the deployment so all 3 replicas reach Running state.

  Useful commands
    kubectl get pods
    kubectl describe pod <name>
    kubectl get deployment web-app -o yaml
"@

Start-Lab -Name 'image-pull' -Title 'Lab 04 - ImagePullBackOff' `
    -Description $desc `
    -DeployFn   { Deploy-Lab } `
    -ValidateFn { Test-LabFix } `
    -HintFn     { param($a) Get-LabHint $a } `
    -SolutionFn { Show-LabSolution }
