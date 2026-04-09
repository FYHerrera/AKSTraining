#Requires -Version 5.1
###############################################################################
# Lab 01 - DNS Resolution Failure (PowerShell)
###############################################################################

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

# ── Deploy ──────────────────────────────────────────────────────────────────
function Deploy-Lab {
    New-AksLabCluster -Scenario 'dns'

    Write-Header 'Injecting Lab Scenario'

    Write-Log 'Applying restrictive NetworkPolicy...'
    @'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
'@ | kubectl apply -f -
    Write-Ok 'NetworkPolicy applied'

    Write-Log 'Deploying test pods...'
    kubectl run dns-test --image=busybox:1.36 --restart=Never -- sh -c 'sleep 3600' 2>$null
    kubectl wait --for=condition=Ready pod/dns-test --timeout=120s 2>$null | Out-Null
    Write-Ok "Test pod 'dns-test' is running"

    kubectl run web --image=nginx:1.25 --labels='app=web' 2>$null
    kubectl expose pod web --port=80 --name=web-svc 2>$null
    Write-Ok "Service 'web-svc' created"

    Write-Host ''
    Write-Separator
    Write-Err 'DNS resolution is BROKEN in the default namespace.'
    Write-Info 'Try:  kubectl exec dns-test -- nslookup kubernetes.default'
    Write-Info 'Use the menu below to validate once you have fixed the issue.'
}

# ── Validate ────────────────────────────────────────────────────────────────
function Test-LabFix {
    $result = kubectl exec dns-test -- nslookup kubernetes.default 2>&1
    if ($result -match 'Address.*10\.') {
        Write-Ok 'DNS resolution is working!'
        return $true
    }
    Write-Err 'DNS resolution still failing.'
    return $false
}

# ── Hint ────────────────────────────────────────────────────────────────────
function Get-LabHint([int]$Attempt) {
    Write-Host ''
    if ($Attempt -lt 2) {
        Write-Info 'Hint 1: Inspect NetworkPolicies in the default namespace.'
        Write-Info '  kubectl get networkpolicy'
    } elseif ($Attempt -lt 4) {
        Write-Info 'Hint 2: The NetworkPolicy blocks ALL egress, including DNS (port 53).'
    } else {
        Write-Info 'Hint 3: Delete the policy or add an egress rule for port 53.'
        Write-Info '  kubectl delete networkpolicy deny-all-egress'
    }
}

# ── Solution ────────────────────────────────────────────────────────────────
function Show-LabSolution {
    Write-Header 'Solution'
    Write-Info 'Option A - Delete the policy:'
    Write-Host '  kubectl delete networkpolicy deny-all-egress' -ForegroundColor Cyan
    Write-Host ''
    Write-Info 'Option B - Allow DNS egress (port 53 UDP/TCP) in the policy.'
    Write-Info 'The original policy had no egress rules, blocking everything.'
}

# ── Run ─────────────────────────────────────────────────────────────────────
$desc = @"
  Scenario
  A team deployed a NetworkPolicy to restrict traffic, but they
  accidentally blocked ALL egress - including DNS (port 53).
  Pods in the default namespace can no longer resolve service names.

  Objective
  Fix the issue so the test pod dns-test can resolve DNS names.

  Useful commands
    kubectl get networkpolicy
    kubectl describe networkpolicy <name>
    kubectl exec dns-test -- nslookup kubernetes.default
"@

Start-Lab -Name 'dns-resolution' -Title 'Lab 01 - DNS Resolution Failure' `
    -Description $desc `
    -DeployFn   { Deploy-Lab } `
    -ValidateFn { Test-LabFix } `
    -HintFn     { param($a) Get-LabHint $a } `
    -SolutionFn { Show-LabSolution }
