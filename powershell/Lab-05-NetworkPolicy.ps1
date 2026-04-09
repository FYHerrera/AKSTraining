#Requires -Version 5.1
###############################################################################
# Lab 05 - Network Policy Blocking Traffic (PowerShell)
###############################################################################

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

# ── Deploy ──────────────────────────────────────────────────────────────────
function Deploy-Lab {
    New-AksLabCluster -Scenario 'netpol'

    Write-Header 'Injecting Lab Scenario'

    Write-Log 'Deploying backend service...'
    @'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        tier: api
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
  name: backend-svc
  namespace: default
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
'@ | kubectl apply -f -
    Write-Ok 'Backend deployment + service created'

    Write-Log 'Deploying frontend pod...'
    kubectl run frontend --image=busybox:1.36 --labels='app=frontend,tier=web' --restart=Never -- sh -c 'sleep 3600' 2>$null
    kubectl wait --for=condition=Ready pod/frontend --timeout=120s 2>$null | Out-Null
    Write-Ok 'Frontend pod created'

    Write-Log 'Applying NetworkPolicy...'
    @'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-ingress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: gateway
    ports:
    - protocol: TCP
      port: 80
'@ | kubectl apply -f -
    Write-Ok 'NetworkPolicy applied'

    Start-Sleep -Seconds 5
    Write-Host ''
    Write-Separator
    Write-Err 'Frontend CANNOT reach the backend service!'
    Write-Info 'Try:  kubectl exec frontend -- wget -qO- http://backend-svc --timeout=5'
}

# ── Validate ────────────────────────────────────────────────────────────────
function Test-LabFix {
    $result = kubectl exec frontend -- wget -qO- http://backend-svc --timeout=10 2>&1
    if ($result -match 'nginx|Welcome') {
        Write-Ok 'Frontend can reach the backend!'
        return $true
    }
    Write-Err 'Frontend still cannot reach the backend.'
    return $false
}

# ── Hint ────────────────────────────────────────────────────────────────────
function Get-LabHint([int]$Attempt) {
    Write-Host ''
    if ($Attempt -lt 2) {
        Write-Info 'Hint 1: Look at the NetworkPolicy applied to backend pods.'
        Write-Info '  kubectl describe networkpolicy backend-allow-ingress'
    } elseif ($Attempt -lt 4) {
        Write-Info 'Hint 2: The ingress allows from a specific label selector.'
        Write-Info '  What label does the frontend pod actually have?'
        Write-Info '  kubectl get pod frontend --show-labels'
    } else {
        Write-Info "Hint 3: Policy allows from 'app=gateway' but frontend has 'app=frontend'."
        Write-Info '  Fix the podSelector in the ingress rule.'
    }
}

# ── Solution ────────────────────────────────────────────────────────────────
function Show-LabSolution {
    Write-Header 'Solution'
    Write-Info "Fix the NetworkPolicy ingress selector from 'app: gateway' to 'app: frontend'."
    Write-Host "  kubectl edit networkpolicy backend-allow-ingress" -ForegroundColor Cyan
    Write-Host "  # Change 'app: gateway' to 'app: frontend' in the ingress.from section" -ForegroundColor Cyan
}

# ── Run ─────────────────────────────────────────────────────────────────────
$desc = @"
  Scenario
  A microservices app has a frontend and a backend service.
  A NetworkPolicy was applied to restrict access to the backend,
  but now the frontend cannot reach the backend service.

  Objective
  Fix it so the frontend pod can reach the backend via backend-svc on port 80.

  Useful commands
    kubectl get pods,svc
    kubectl get networkpolicy
    kubectl describe networkpolicy <name>
    kubectl exec frontend -- wget -qO- http://backend-svc --timeout=5
"@

Start-Lab -Name 'network-policy' -Title 'Lab 05 - Network Policy Blocking Traffic' `
    -Description $desc `
    -DeployFn   { Deploy-Lab } `
    -ValidateFn { Test-LabFix } `
    -HintFn     { param($a) Get-LabHint $a } `
    -SolutionFn { Show-LabSolution }
