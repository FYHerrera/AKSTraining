#Requires -Version 5.1
###############################################################################
# Lab 03 - CrashLoopBackOff (PowerShell)
###############################################################################

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

# ── Deploy ──────────────────────────────────────────────────────────────────
function Deploy-Lab {
    New-AksLabCluster -Scenario 'crashloop'

    Write-Header 'Injecting Lab Scenario'

    Write-Log 'Creating deployment with bad liveness probe...'
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
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
          failureThreshold: 2
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
'@ | kubectl apply -f -
    Write-Ok "Deployment 'web-app' created"

    Write-Log 'Waiting for containers to start crashing...'
    Start-Sleep -Seconds 25

    Write-Host ''
    Write-Separator
    Write-Err 'Pods are entering CrashLoopBackOff!'
    kubectl get pods -l app=web-app --no-headers 2>$null
    Write-Info 'Investigate why the pods keep restarting.'
}

# ── Validate ────────────────────────────────────────────────────────────────
function Test-LabFix {
    $ready = (kubectl get pods -l app=web-app --no-headers 2>$null |
        Select-String 'Running' | Select-String '1/1' | Measure-Object).Count
    if ($ready -ge 2) {
        Write-Ok 'Both replicas are Running and Ready!'
        return $true
    }
    Write-Err 'Not all replicas are healthy yet.'
    kubectl get pods -l app=web-app --no-headers 2>$null
    return $false
}

# ── Hint ────────────────────────────────────────────────────────────────────
function Get-LabHint([int]$Attempt) {
    Write-Host ''
    if ($Attempt -lt 2) {
        Write-Info 'Hint 1: Describe a pod and look at liveness probe failures.'
    } elseif ($Attempt -lt 4) {
        Write-Info 'Hint 2: nginx listens on port 80. What port does the probe use?'
    } else {
        Write-Info 'Hint 3: Fix liveness probe: port 8080->80, path /healthz->/'
    }
}

# ── Solution ────────────────────────────────────────────────────────────────
function Show-LabSolution {
    Write-Header 'Solution'
    Write-Info 'Fix the liveness probe port and path:'
    Write-Host "  kubectl patch deployment web-app --type=json -p='[" -ForegroundColor Cyan
    Write-Host '    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80},' -ForegroundColor Cyan
    Write-Host '    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/"}' -ForegroundColor Cyan
    Write-Host "  ]'" -ForegroundColor Cyan
    Write-Host ''
    Write-Info 'nginx listens on 80 at /. Probe targeted 8080 at /healthz.'
}

# ── Run ─────────────────────────────────────────────────────────────────────
$desc = @"
  Scenario
  The web-app deployment was working fine until someone changed
  the health-check configuration. Now all pods are in CrashLoopBackOff.

  Objective
  Fix the deployment so all 2 replicas are Running and Ready (1/1).

  Useful commands
    kubectl get pods
    kubectl describe pod <name>
    kubectl logs <pod-name>
    kubectl get deployment web-app -o yaml
"@

Start-Lab -Name 'crashloop' -Title 'Lab 03 - CrashLoopBackOff' `
    -Description $desc `
    -DeployFn   { Deploy-Lab } `
    -ValidateFn { Test-LabFix } `
    -HintFn     { param($a) Get-LabHint $a } `
    -SolutionFn { Show-LabSolution }
