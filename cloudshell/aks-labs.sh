#!/usr/bin/env bash
###############################################################################
# AKS Troubleshooting Labs – Cloud Shell Edition
#
# Single-file launcher for Azure Cloud Shell. Upload and run:
#   chmod +x aks-labs.sh && ./aks-labs.sh
#
# Or run a specific lab directly:
#   ./aks-labs.sh 1    # Lab 01 - DNS Resolution
#   ./aks-labs.sh 3    # Lab 03 - CrashLoopBackOff
###############################################################################

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Config ───────────────────────────────────────────────────────────────────
REGION="${AKS_LAB_REGION:-canadacentral}"
NODE_COUNT="${AKS_LAB_NODE_COUNT:-1}"
VM_SIZE="${AKS_LAB_VM_SIZE:-Standard_D8ds_v5}"
K8S_VERSION="" RESOURCE_GROUP="" CLUSTER_NAME="" MC_RG=""
LAB_START="" LOG_FILE=""

# ── Logging ──────────────────────────────────────────────────────────────────
_log() { [[ -n "${LOG_FILE:-}" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }
log()  { echo -e "${NC}[$(date '+%H:%M:%S')] $1${NC}"; _log "$1"; }
ok()   { echo -e "${GREEN}  [✓] $1${NC}"; _log "[OK] $1"; }
err()  { echo -e "${RED}  [✗] $1${NC}"; _log "[ERR] $1"; }
warn() { echo -e "${YELLOW}  [!] $1${NC}"; _log "[WARN] $1"; }
info() { echo -e "${CYAN}  [i] $1${NC}"; _log "[INFO] $1"; }

header() {
    echo ""
    echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}    $1${NC}"
    echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"
    echo ""
}
sep() { echo -e "${BLUE}  ───────────────────────────────────────────────────────${NC}"; }

# ── Ctrl+C trap ──────────────────────────────────────────────────────────────
_trap() { echo ""; warn "Interrupted"; [[ -n "${RESOURCE_GROUP:-}" ]] && _cleanup; exit 130; }
trap _trap INT TERM

# ── Name gen ─────────────────────────────────────────────────────────────────
_name() { echo "aks-lab-$1-$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 4)"; }

# ── Pre-flight ───────────────────────────────────────────────────────────────
_preflight() {
    header "Pre-flight Checks"
    command -v az &>/dev/null  && ok "Azure CLI $(az version --query '"azure-cli"' -o tsv 2>/dev/null)" || { err "az not found"; exit 1; }
    command -v kubectl &>/dev/null && ok "kubectl found" || { az aks install-cli 2>/dev/null; ok "kubectl installed"; }
    command -v jq &>/dev/null && ok "jq found" || { err "jq not found"; exit 1; }

    local acct; acct=$(az account show -o json 2>/dev/null) || { err "Not logged in. Run: az login"; exit 1; }

    # Required Azure resource providers
    local required_providers=("Microsoft.ContainerService" "Microsoft.Network" "Microsoft.Compute" "Microsoft.Storage" "Microsoft.ManagedIdentity" "Microsoft.OperationsManagement" "Microsoft.OperationalInsights")
    local missing=()
    for p in "${required_providers[@]}"; do
        local st; st=$(az provider show --namespace "$p" --query registrationState -o tsv 2>/dev/null || echo "")
        [[ "$st" == "Registered" ]] && ok "$p" || { err "$p NOT registered ($st)"; missing+=("$p"); }
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""; warn "${#missing[@]} provider(s) need registration:"
        for p in "${missing[@]}"; do echo -e "    ${YELLOW}- $p${NC}"; done
        echo ""; echo -ne "${BOLD}  Register all now? (y/n): ${NC}"; read -r rc
        if [[ "${rc,,}" =~ ^y ]]; then
            for p in "${missing[@]}"; do log "Registering $p..."; az provider register --namespace "$p" -o none; done
            log "Waiting for registration (2-5 min)..."
            for p in "${missing[@]}"; do
                local wc=0
                while [[ "$(az provider show --namespace "$p" --query registrationState -o tsv 2>/dev/null)" != "Registered" ]]; do
                    ((wc++)); [[ $wc -ge 30 ]] && { err "Timeout on $p"; exit 1; }; sleep 10
                done; ok "$p registered"
            done
        else
            err "Cannot proceed without providers."; info "Register manually:"
            for p in "${missing[@]}"; do echo -e "  ${CYAN}az provider register --namespace $p${NC}"; done; exit 1
        fi
    fi
    ok "User: $(echo "$acct" | jq -r '.user.name')"
    ok "Sub:  $(echo "$acct" | jq -r '.name') ($(echo "$acct" | jq -r '.id'))"
    echo ""; info "All checks passed!"; echo ""
}

# ── Create AKS ───────────────────────────────────────────────────────────────
_create_aks() {
    local scenario="$1"; shift
    CLUSTER_NAME=$(_name "$scenario"); RESOURCE_GROUP="${CLUSTER_NAME}-rg"
    K8S_VERSION=$(az aks get-versions -l "$REGION" --query "values[?isDefault].version" -o tsv 2>/dev/null || echo "1.29")

    header "Creating Lab Environment"
    info "RG: $RESOURCE_GROUP | Cluster: $CLUSTER_NAME"
    info "Region: $REGION | Nodes: $NODE_COUNT × $VM_SIZE | K8s: $K8S_VERSION"
    echo ""

    log "Creating resource group..."
    az group create -n "$RESOURCE_GROUP" -l "$REGION" -o none
    ok "Resource group created"

    log "Creating AKS cluster (~5-10 min)..."
    az aks create -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" \
        --node-count "$NODE_COUNT" --node-vm-size "$VM_SIZE" \
        --kubernetes-version "$K8S_VERSION" -l "$REGION" \
        --generate-ssh-keys --network-plugin azure -o none "$@"
    ok "AKS cluster created"

    log "Getting credentials..."
    az aks get-credentials -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --overwrite-existing
    ok "kubectl configured"

    MC_RG=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query nodeResourceGroup -o tsv 2>/dev/null)

    log "Verifying cluster health..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s &>/dev/null || true
    ok "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')/$NODE_COUNT nodes Ready"
}

# ── Cleanup ──────────────────────────────────────────────────────────────────
_cleanup() {
    echo ""; sep
    echo -ne "${YELLOW}  Delete all lab resources? (y/n): ${NC}"; read -r r
    if [[ "${r,,}" =~ ^y ]]; then
        az group delete -n "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
        ok "Deletion initiated (background)"
    else
        warn "Kept. Delete later: az group delete -n $RESOURCE_GROUP --yes"
    fi
}

# ── Menu loop ────────────────────────────────────────────────────────────────
_menu() {
    local vfn="$1" hfn="$2" sfn="$3"; local attempt=0
    while true; do
        echo ""; sep
        echo -e "${BOLD}  Lab Menu${NC}"; sep
        echo -e "    ${GREEN}[V]${NC} Validate   ${YELLOW}[H]${NC} Hint   ${CYAN}[S]${NC} Solution   ${RED}[Q]${NC} Quit"
        echo -ne "${BOLD}  > ${NC}"; read -r c
        case "${c,,}" in
            v) attempt=$((attempt+1)); info "Attempt #$attempt"
               if $vfn; then
                   header "Lab Completed!"
                   local e=$(($(date +%s)-LAB_START))
                   ok "Time: $((e/60))m $((e%60))s | Attempts: $attempt"
                   _cleanup; return 0
               fi ;;
            h) $hfn "$attempt" ;;
            s) echo -ne "${YELLOW}  Show solution? (y/n): ${NC}"; read -r x
               [[ "${x,,}" =~ ^y ]] && $sfn ;;
            q) _cleanup; return 1 ;;
            *) warn "Use V, H, S or Q" ;;
        esac
    done
}

###############################################################################
#                              LAB DEFINITIONS                                #
###############################################################################

# ═════════════════════════════════════════════════════════════════════════════
# LAB 01 – DNS Resolution Failure
# ═════════════════════════════════════════════════════════════════════════════
lab01_deploy() {
    _create_aks dns
    header "Injecting Problem"
    kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF
    ok "NetworkPolicy applied"
    kubectl run dns-test --image=busybox:1.36 --restart=Never -- sh -c "sleep 3600" 2>/dev/null || true
    kubectl wait --for=condition=Ready pod/dns-test --timeout=120s &>/dev/null
    kubectl run web --image=nginx:1.25 --labels="app=web" 2>/dev/null || true
    kubectl expose pod web --port=80 --name=web-svc 2>/dev/null || true
    ok "Test pods deployed"
    echo ""; sep
    err "DNS resolution is BROKEN in the default namespace."
    info "Try:  kubectl exec dns-test -- nslookup kubernetes.default"
}
lab01_validate() {
    local r; r=$(kubectl exec dns-test -- nslookup kubernetes.default 2>&1) || true
    echo "$r" | grep -q "Address.*10\." && { ok "DNS works!"; return 0; }
    err "DNS still failing."; return 1
}
lab01_hint() {
    echo ""
    [[ ${1:-0} -lt 2 ]] && { info "Check NetworkPolicies: kubectl get networkpolicy"; return; }
    [[ ${1:-0} -lt 4 ]] && { info "The policy blocks ALL egress, including DNS (port 53 UDP/TCP)."; return; }
    info "Delete it: kubectl delete networkpolicy deny-all-egress"
    info "Or add egress rule allowing port 53."
}
lab01_solution() {
    header "Solution"
    echo -e "  ${CYAN}kubectl delete networkpolicy deny-all-egress${NC}"
    echo ""; info "Or allow DNS egress (port 53 UDP+TCP) in the policy."
    info "The policy had policyTypes: Egress but no egress rules → blocks everything."
}

# ═════════════════════════════════════════════════════════════════════════════
# LAB 02 – Pod Stuck in Pending
# ═════════════════════════════════════════════════════════════════════════════
lab02_deploy() {
    _create_aks pending
    header "Injecting Problem"
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
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
EOF
    ok "Deployment created"; sleep 5
    echo ""; sep; err "All pods are stuck in Pending!"
    info "Investigate: kubectl describe pod <pod-name>"
}
lab02_validate() {
    local r; r=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep -c Running || echo 0)
    [[ "$r" -ge 3 ]] && { ok "All 3 replicas Running!"; return 0; }
    err "$r/3 Running."; return 1
}
lab02_hint() {
    echo ""
    [[ ${1:-0} -lt 2 ]] && { info "Describe a pending pod → Events section."; return; }
    [[ ${1:-0} -lt 4 ]] && { info "nodeSelector requires 'disktype=ssd'. Check node labels."; return; }
    info "Fix: kubectl label nodes --all disktype=ssd"
    info "Or remove nodeSelector from the deployment."
}
lab02_solution() {
    header "Solution"
    echo -e "  ${CYAN}kubectl label nodes --all disktype=ssd${NC}"
    echo ""; info "Or: kubectl patch deployment web-app --type=json -p='[{\"op\":\"remove\",\"path\":\"/spec/template/spec/nodeSelector\"}]'"
}

# ═════════════════════════════════════════════════════════════════════════════
# LAB 03 – CrashLoopBackOff
# ═════════════════════════════════════════════════════════════════════════════
lab03_deploy() {
    _create_aks crashloop
    header "Injecting Problem"
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
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
EOF
    ok "Deployment created"; log "Waiting for crash cycle..."; sleep 25
    echo ""; sep; err "Pods are in CrashLoopBackOff!"
    kubectl get pods -l app=web-app --no-headers 2>/dev/null
}
lab03_validate() {
    local r; r=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep Running | grep -c "1/1" || echo 0)
    [[ "$r" -ge 2 ]] && { ok "Both replicas Running & Ready!"; return 0; }
    err "Not all healthy yet."; return 1
}
lab03_hint() {
    echo ""
    [[ ${1:-0} -lt 2 ]] && { info "Describe pod → look at liveness probe failures in Events."; return; }
    [[ ${1:-0} -lt 4 ]] && { info "nginx listens on port 80. What port is the probe using?"; return; }
    info "Fix: port 8080→80, path /healthz→/"
}
lab03_solution() {
    header "Solution"
    echo -e "  ${CYAN}kubectl patch deployment web-app --type=json -p='["
    echo -e "    {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/livenessProbe/httpGet/port\",\"value\":80},"
    echo -e "    {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/livenessProbe/httpGet/path\",\"value\":\"/\"}"
    echo -e "  ]'${NC}"
    echo ""; info "nginx serves on port 80 at /. Probe targeted port 8080 at /healthz."
}

# ═════════════════════════════════════════════════════════════════════════════
# LAB 04 – ImagePullBackOff
# ═════════════════════════════════════════════════════════════════════════════
lab04_deploy() {
    _create_aks imagepull
    header "Injecting Problem"
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
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
EOF
    ok "Deployment created"; sleep 15
    echo ""; sep; err "Pods in ImagePullBackOff!"
    kubectl get pods -l app=web-app --no-headers 2>/dev/null
}
lab04_validate() {
    local r; r=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep -c Running || echo 0)
    [[ "$r" -ge 3 ]] && { ok "All 3 replicas Running!"; return 0; }
    err "$r/3 Running."; return 1
}
lab04_hint() {
    echo ""
    [[ ${1:-0} -lt 2 ]] && { info "Describe pod → check Events for image pull errors."; return; }
    [[ ${1:-0} -lt 4 ]] && { info "Does the image tag 'nginx:99.99.99' exist on Docker Hub?"; return; }
    info "Fix: kubectl set image deployment/web-app nginx=nginx:1.25"
}
lab04_solution() {
    header "Solution"
    echo -e "  ${CYAN}kubectl set image deployment/web-app nginx=nginx:1.25${NC}"
    echo ""; info "Tag 'nginx:99.99.99' doesn't exist. Use a valid tag like 1.25."
}

# ═════════════════════════════════════════════════════════════════════════════
# LAB 05 – Network Policy Blocking Traffic
# ═════════════════════════════════════════════════════════════════════════════
lab05_deploy() {
    _create_aks netpol
    header "Injecting Problem"
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
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
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
EOF
    ok "Backend deployed"
    kubectl run frontend --image=busybox:1.36 --labels="app=frontend,tier=web" \
        --restart=Never -- sh -c "sleep 3600" 2>/dev/null || true
    kubectl wait --for=condition=Ready pod/frontend --timeout=120s &>/dev/null
    kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-ingress
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
EOF
    ok "NetworkPolicy applied"; sleep 5
    echo ""; sep; err "Frontend CANNOT reach the backend!"
    info "Try: kubectl exec frontend -- wget -qO- http://backend-svc --timeout=5"
}
lab05_validate() {
    local r; r=$(kubectl exec frontend -- wget -qO- http://backend-svc --timeout=10 2>&1) || true
    echo "$r" | grep -qi "nginx\|Welcome" && { ok "Frontend→Backend works!"; return 0; }
    err "Still blocked."; return 1
}
lab05_hint() {
    echo ""
    [[ ${1:-0} -lt 2 ]] && { info "Describe networkpolicy backend-allow-ingress."; return; }
    [[ ${1:-0} -lt 4 ]] && { info "Ingress allows from 'app=??'. Frontend has 'app=??'. Match?"; return; }
    info "Policy allows 'app: gateway' but frontend has 'app: frontend'."
    info "Fix the podSelector in the ingress rule."
}
lab05_solution() {
    header "Solution"
    info "Edit the NetworkPolicy ingress from.podSelector:"
    echo -e "  ${CYAN}kubectl edit networkpolicy backend-allow-ingress${NC}"
    info "Change 'app: gateway' → 'app: frontend'"
}

# ═════════════════════════════════════════════════════════════════════════════
# LAB 06 – Node Taint / Scheduling Issue
# ═════════════════════════════════════════════════════════════════════════════
lab06_deploy() {
    _create_aks taint
    header "Injecting Problem"
    for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
        kubectl taint nodes "$n" maintenance=scheduled:NoSchedule --overwrite 2>/dev/null || true
    done
    ok "Taints applied"
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
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
EOF
    ok "Deployment created"; sleep 8
    echo ""; sep; err "All pods Pending – no node accepts them!"
    kubectl get pods -l app=web-app --no-headers 2>/dev/null
}
lab06_validate() {
    local r; r=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep -c Running || echo 0)
    [[ "$r" -ge 3 ]] && { ok "All 3 replicas Running!"; return 0; }
    err "$r/3 Running."; return 1
}
lab06_hint() {
    echo ""
    [[ ${1:-0} -lt 2 ]] && { info "Describe a pending pod → check scheduling warnings."; return; }
    [[ ${1:-0} -lt 4 ]] && { info "Check node taints: kubectl describe node <name> | grep -A5 Taints"; return; }
    info "Fix: kubectl taint nodes --all maintenance=scheduled:NoSchedule-"
}
lab06_solution() {
    header "Solution"
    echo -e "  ${CYAN}kubectl taint nodes --all maintenance=scheduled:NoSchedule-${NC}"
    echo ""; info "The trailing '-' removes the taint. Or add a toleration to the deployment."
}

# ═════════════════════════════════════════════════════════════════════════════
# LAB 07 – NSG Blocking Traffic
# ═════════════════════════════════════════════════════════════════════════════
NSG_NAME="" DENY_RULE="DenyInbound80"
lab07_deploy() {
    _create_aks nsg
    header "Injecting Problem"
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
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
spec:
  type: LoadBalancer
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
EOF
    ok "Deployment + LoadBalancer created"
    log "Waiting for external IP (~2 min)..."
    local ip=""
    for i in $(seq 1 30); do
        ip=$(kubectl get svc web-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        [[ -n "$ip" && "$ip" != "null" ]] && break; sleep 10
    done
    [[ -z "$ip" || "$ip" == "null" ]] && { err "No external IP. Setup failed."; return 1; }
    ok "External IP: $ip"

    NSG_NAME=$(az network nsg list -g "$MC_RG" --query '[0].name' -o tsv 2>/dev/null)
    [[ -z "$NSG_NAME" ]] && { err "NSG not found."; return 1; }

    az network nsg rule create -g "$MC_RG" --nsg-name "$NSG_NAME" \
        -n "$DENY_RULE" --priority 100 --direction Inbound --access Deny \
        --protocol Tcp --destination-port-ranges 80 \
        --source-address-prefixes '*' --destination-address-prefixes '*' -o none 2>/dev/null
    ok "NSG deny rule added"
    echo ""; sep
    err "External traffic to port 80 is BLOCKED!"
    info "IP: $ip | MC RG: $MC_RG | NSG: $NSG_NAME"
    info "Pods run fine, service has IP, but HTTP times out. Azure networking issue."
}
lab07_validate() {
    local r; r=$(az network nsg rule show -g "$MC_RG" --nsg-name "$NSG_NAME" -n "$DENY_RULE" 2>&1) || true
    if echo "$r" | grep -q "ResourceNotFound\|not found\|could not be found"; then
        ok "NSG deny rule removed!"; return 0
    fi
    err "Rule '$DENY_RULE' still exists."; return 1
}
lab07_hint() {
    echo ""
    [[ ${1:-0} -lt 2 ]] && { info "Issue is Azure networking, not K8s. Check NSGs."; return; }
    [[ ${1:-0} -lt 4 ]] && { info "az network nsg rule list --nsg-name $NSG_NAME -g $MC_RG -o table"; return; }
    info "Delete: az network nsg rule delete --nsg-name $NSG_NAME -g $MC_RG -n $DENY_RULE"
}
lab07_solution() {
    header "Solution"
    echo -e "  ${CYAN}az network nsg rule delete -g $MC_RG --nsg-name $NSG_NAME -n $DENY_RULE${NC}"
    echo ""; info "NSG rule '$DENY_RULE' (priority 100) denies all inbound TCP/80."
}

###############################################################################
#                                 LAUNCHER                                    #
###############################################################################

run_lab() {
    local num="$1"
    LOG_FILE="/tmp/aks-lab-$(date '+%Y%m%d-%H%M%S').log"
    LAB_START=$(date +%s)
    _preflight
    case "$num" in
        1) header "Lab 01 – DNS Resolution Failure"
           echo -e "  A NetworkPolicy blocks ALL egress, breaking DNS.\n  Fix it so ${CYAN}dns-test${NC} can resolve names.\n"
           lab01_deploy; _menu lab01_validate lab01_hint lab01_solution ;;
        2) header "Lab 02 – Pod Stuck in Pending"
           echo -e "  Pods can't schedule. Cluster has resources, but something prevents it.\n  Make all 3 replicas ${GREEN}Running${NC}.\n"
           lab02_deploy; _menu lab02_validate lab02_hint lab02_solution ;;
        3) header "Lab 03 – CrashLoopBackOff"
           echo -e "  Health check config changed, now pods keep crashing.\n  Fix it so both replicas are ${GREEN}Ready (1/1)${NC}.\n"
           lab03_deploy; _menu lab03_validate lab03_hint lab03_solution ;;
        4) header "Lab 04 – ImagePullBackOff"
           echo -e "  Typo in image tag. Pods stuck in ${RED}ImagePullBackOff${NC}.\n  Fix the image so all 3 replicas ${GREEN}Running${NC}.\n"
           lab04_deploy; _menu lab04_validate lab04_hint lab04_solution ;;
        5) header "Lab 05 – Network Policy Blocking Traffic"
           echo -e "  Frontend can't reach backend. A NetworkPolicy is misconfigured.\n  Fix it so frontend → backend works on port 80.\n"
           lab05_deploy; _menu lab05_validate lab05_hint lab05_solution ;;
        6) header "Lab 06 – Node Taint Issue"
           echo -e "  Maintenance taints left on all nodes. Pods stuck ${RED}Pending${NC}.\n  Fix so all 3 replicas are ${GREEN}Running${NC}.\n"
           lab06_deploy; _menu lab06_validate lab06_hint lab06_solution ;;
        7) header "Lab 07 – NSG Blocking Inbound Traffic"
           echo -e "  LoadBalancer service has IP but HTTP times out.\n  Azure networking issue blocks port 80.\n"
           lab07_deploy; _menu lab07_validate lab07_hint lab07_solution ;;
        *) err "Invalid lab number: $num"; exit 1 ;;
    esac
}

show_menu() {
    header "AKS Troubleshooting Labs"
    echo -e "  ${BOLD}Select a lab:${NC}"
    echo ""
    echo -e "    ${GREEN}1${NC}  DNS Resolution Failure           ${YELLOW}★★☆${NC}"
    echo -e "    ${GREEN}2${NC}  Pod Stuck in Pending              ${YELLOW}★☆☆${NC}"
    echo -e "    ${GREEN}3${NC}  CrashLoopBackOff                  ${YELLOW}★★☆${NC}"
    echo -e "    ${GREEN}4${NC}  ImagePullBackOff                  ${YELLOW}★☆☆${NC}"
    echo -e "    ${GREEN}5${NC}  Network Policy Blocking Traffic   ${YELLOW}★★★${NC}"
    echo -e "    ${GREEN}6${NC}  Node Taint / Scheduling Issue     ${YELLOW}★★☆${NC}"
    echo -e "    ${GREEN}7${NC}  NSG Blocking Inbound Traffic      ${YELLOW}★★★${NC}"
    echo ""
    echo -e "    ${RED}0${NC}  Exit"
    echo ""
    echo -ne "${BOLD}  Select (1-7): ${NC}"
    read -r choice
    [[ "$choice" == "0" ]] && { echo "Bye!"; exit 0; }
    run_lab "$choice"
}

# ── Entry point ──────────────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    run_lab "$1"
else
    show_menu
fi
