#!/usr/bin/env bash
###############################################################################
# Lab 10 – Multi-Problem Challenge  (STANDALONE)
#
# Scenario : A cluster has 4 combined problems. Apply everything learned.
# Objective: Get all apps healthy and accessible.
#
# Usage:  chmod +x lab-10.sh && ./lab-10.sh
###############################################################################

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

DEFAULT_REGION="${AKS_LAB_REGION:-canadacentral}"
DEFAULT_NODE_COUNT="${AKS_LAB_NODE_COUNT:-1}"
DEFAULT_VM_SIZE="${AKS_LAB_VM_SIZE:-Standard_D8ds_v5}"
K8S_VERSION=""
LOG_DIR=""; LOG_FILE=""; RESOURCE_GROUP=""; CLUSTER_NAME=""
MC_RESOURCE_GROUP=""; LAB_START_TIME=""

###############################################################################
# Common Functions (embedded)
###############################################################################
log_to_file() { [[ -n "${LOG_FILE:-}" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }
log()    { echo -e "${NC}[$(date '+%H:%M:%S')] $1${NC}";  log_to_file "$1"; }
ok()     { echo -e "${GREEN}  [✓] $1${NC}";               log_to_file "[OK] $1"; }
err()    { echo -e "${RED}  [✗] $1${NC}";                 log_to_file "[ERROR] $1"; }
warn()   { echo -e "${YELLOW}  [!] $1${NC}";              log_to_file "[WARN] $1"; }
info()   { echo -e "${CYAN}  [i] $1${NC}";                log_to_file "[INFO] $1"; }
header() { echo ""; echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}${BLUE}    $1${NC}"; echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"; echo ""; }
separator() { echo -e "${BLUE}  ───────────────────────────────────────────────────────${NC}"; }
init_logging() { local lab_name="$1"; SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LOG_DIR="${HOME}/aks-lab-logs"; mkdir -p "$LOG_DIR"; LOG_FILE="${LOG_DIR}/${lab_name}-$(date '+%Y%m%d-%H%M%S').log"; log_to_file "=== Lab session started: $lab_name ==="; }
cleanup_on_interrupt() { echo ""; warn "Interrupted by user (Ctrl+C)"; [[ -n "${RESOURCE_GROUP:-}" ]] && cleanup_resources; exit 130; }
trap cleanup_on_interrupt INT TERM
generate_name() { local s; s=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 4); echo "lab-${1}-${s}"; }

check_prerequisites() {
    header "Pre-flight Checks"
    if ! command -v az &>/dev/null; then err "Azure CLI not installed."; exit 1; fi
    ok "Azure CLI found ($(az version --query '\"azure-cli\"' -o tsv 2>/dev/null))"
    if ! command -v kubectl &>/dev/null; then warn "kubectl not found – installing..."; az aks install-cli 2>/dev/null || true; fi
    command -v kubectl &>/dev/null && ok "kubectl found" || { err "kubectl not installed."; exit 1; }
    if ! command -v jq &>/dev/null; then err "jq not installed."; exit 1; fi; ok "jq found"
    local account; account=$(az account show -o json 2>/dev/null) || true
    if [[ -z "$account" ]]; then err "Not logged into Azure. Run: az login"; exit 1; fi
    ok "Logged in as: $(echo "$account" | jq -r '.user.name')"
    ok "Subscription: $(echo "$account" | jq -r '.name') ($(echo "$account" | jq -r '.id'))"
    local required_providers=("Microsoft.ContainerService" "Microsoft.Network" "Microsoft.Compute" "Microsoft.Storage" "Microsoft.ManagedIdentity" "Microsoft.OperationsManagement" "Microsoft.OperationalInsights")
    local missing=()
    for p in "${required_providers[@]}"; do local state; state=$(az provider show --namespace "$p" --query "registrationState" -o tsv 2>/dev/null || echo ""); [[ "$state" == "Registered" ]] && ok "$p registered" || { err "$p NOT registered"; missing+=("$p"); }; done
    if [[ ${#missing[@]} -gt 0 ]]; then echo -ne "${BOLD}  Register missing providers? (y/n): ${NC}"; read -r ans
        if [[ "${ans,,}" =~ ^y ]]; then for p in "${missing[@]}"; do az provider register --namespace "$p" -o none; done; for p in "${missing[@]}"; do local w=0; while [[ "$(az provider show --namespace "$p" --query 'registrationState' -o tsv 2>/dev/null)" != "Registered" ]]; do ((w++)); [[ $w -ge 30 ]] && { err "Timeout for $p"; exit 1; }; sleep 10; done; ok "$p registered"; done
        else err "Cannot proceed without providers."; exit 1; fi; fi
    echo ""; info "All pre-flight checks passed!"; echo ""
}

get_latest_k8s_version() { local region="${1:-$DEFAULT_REGION}"; K8S_VERSION=$(az aks get-versions --location "$region" --query "values[?isDefault].version" -o tsv 2>/dev/null || echo ""); if [[ -z "$K8S_VERSION" ]]; then K8S_VERSION="1.29"; warn "Defaulting to K8s $K8S_VERSION"; fi; }

create_aks_cluster() {
    local scenario="$1"; local extra_args="${2:-}"
    CLUSTER_NAME=$(generate_name "$scenario"); RESOURCE_GROUP="${CLUSTER_NAME}-rg"
    header "Creating Lab Environment"
    info "Resource Group : $RESOURCE_GROUP"; info "Cluster Name   : $CLUSTER_NAME"; info "Region         : $DEFAULT_REGION"; info "Node Count     : $DEFAULT_NODE_COUNT"; info "VM Size        : $DEFAULT_VM_SIZE"; echo ""
    log "Creating resource group..."; az group create --name "$RESOURCE_GROUP" --location "$DEFAULT_REGION" -o none; ok "Resource group created"
    get_latest_k8s_version "$DEFAULT_REGION"; info "Kubernetes version: $K8S_VERSION"
    log "Creating AKS cluster (5-10 min)..."
    local cmd="az aks create --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $DEFAULT_NODE_COUNT --node-vm-size $DEFAULT_VM_SIZE --kubernetes-version $K8S_VERSION --location $DEFAULT_REGION --generate-ssh-keys --network-plugin azure -o none"
    [[ -n "$extra_args" ]] && cmd="$cmd $extra_args"; eval "$cmd"; ok "AKS cluster created"
    log "Fetching credentials..."; az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing; ok "kubectl configured"
    MC_RESOURCE_GROUP=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "nodeResourceGroup" -o tsv 2>/dev/null || echo "")
    verify_cluster_health
}

verify_cluster_health() { log "Verifying cluster health..."; kubectl wait --for=condition=Ready nodes --all --timeout=300s &>/dev/null || warn "Some nodes not ready"; local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '/Ready/{n++} END{print n+0}'); ok "$ready/$DEFAULT_NODE_COUNT nodes Ready"; local tries=0; while [[ $tries -lt 12 ]]; do local bad; bad=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '!/Running|Completed/{n++} END{print n+0}'); [[ "$bad" -eq 0 ]] && break; tries=$((tries+1)); sleep 10; done; ok "System pods healthy"; }
cleanup_resources() { echo ""; separator; echo -ne "${YELLOW}  Delete all lab resources? (y/n): ${NC}"; read -r response; if [[ "${response,,}" =~ ^y ]]; then log "Deleting resource group $RESOURCE_GROUP..."; az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true; ok "Deletion initiated."; else warn "Resources kept."; warn "Delete later: az group delete --name $RESOURCE_GROUP --yes"; fi; }

show_connect_info() { echo ""; separator; header "Open a new Cloud Shell tab to work on the lab"; info "Click this link to open a new Cloud Shell session:"; echo -e "  ${CYAN}https://shell.azure.com/bash${NC}"; echo ""; info "Then run this command to connect to the cluster:"; echo -e "  ${GREEN}az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing${NC}"; echo ""; }

interactive_menu() {
    local validate_fn="$1" hint_fn="$2" solution_fn="$3"; local attempt=0
    while true; do echo ""; separator; echo -e "${BOLD}  Lab Menu${NC}"; separator; echo -e "    ${GREEN}[V]${NC}  Validate my fix"; echo -e "    ${YELLOW}[H]${NC}  Request a hint"; echo -e "    ${CYAN}[S]${NC}  Show solution"; echo -e "    ${BLUE}[C]${NC}  Connect to cluster (new tab)"; echo -e "    ${RED}[Q]${NC}  Quit & Cleanup"; echo ""; echo -ne "${BOLD}  Choose an option: ${NC}"; read -r choice
        case "${choice,,}" in v|validate) attempt=$((attempt+1)); info "Validation attempt #$attempt"; if $validate_fn; then echo ""; header "Lab Completed Successfully!"; local end elapsed mins secs; end=$(date +%s); elapsed=$((end - LAB_START_TIME)); mins=$((elapsed / 60)); secs=$((elapsed % 60)); ok "Time: ${mins}m ${secs}s  |  Attempts: $attempt"; cleanup_resources; return 0; fi ;; h|hint) $hint_fn "$attempt" ;; s|solution) echo -ne "${YELLOW}  Show full solution? (y/n): ${NC}"; read -r c; [[ "${c,,}" =~ ^y ]] && $solution_fn ;; c|connect) show_connect_info ;; q|quit) cleanup_resources; return 1 ;; *) warn "Invalid choice." ;; esac; done
}

run_lab() { local lab_name="$1" lab_title="$2" lab_desc="$3" deploy_fn="$4" validate_fn="$5" hint_fn="$6" solution_fn="$7"; LAB_START_TIME=$(date +%s); init_logging "$lab_name"; header "$lab_title"; echo -e "$lab_desc"; echo ""; check_prerequisites; $deploy_fn; show_connect_info; interactive_menu "$validate_fn" "$hint_fn" "$solution_fn"; }

###############################################################################
# Lab 10 – Multi-Problem Challenge
###############################################################################
LAB_NAME="adv-tshoot"
LAB_TITLE="Lab 10 – Multi-Problem Challenge"
LAB_DESC="
  ${BOLD}Scenario${NC}
  An intern deployed a full application stack but ${RED}nothing works${NC}.
  There are ${RED}4 separate problems${NC} that you need to find and fix.

  ${BOLD}Objective${NC}
  Fix ALL issues so that:
    1. All pods in ${CYAN}challenge${NC} namespace are ${GREEN}Running${NC}
    2. The frontend can reach the backend via ${CYAN}backend-svc${NC}
    3. DNS resolution works
    4. The ConfigMap exists with required keys

  ${BOLD}Apply the DISCOVER framework:${NC}
    D-Define  I-Investigate  S-Scope  C-Compare
    O-Options  V-Verify  E-Execute  R-Review

  ${BOLD}Start investigating:${NC}
    kubectl get all -n challenge
    kubectl get events -n challenge --sort-by='.lastTimestamp'
"

deploy() {
    create_aks_cluster "$LAB_NAME" "--network-policy azure"
    header "Injecting Lab Scenario (4 problems)"

    kubectl create namespace challenge 2>/dev/null || true

    # Problem 1: Wrong image tag
    log "Problem 1: Deploying backend with wrong image..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: challenge
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
      - name: api
        image: nginx:does-not-exist-tag
        ports:
        - containerPort: 80
EOF
    ok "Backend deployed (broken image)"

    # Problem 2: Service selector mismatch
    log "Problem 2: Creating Service with wrong selector..."
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: challenge
spec:
  selector:
    app: back-end
  ports:
  - port: 80
    targetPort: 80
EOF
    ok "Service created (wrong selector)"

    # Problem 3: Missing ConfigMap
    log "Problem 3: Deploying frontend with missing ConfigMap..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: challenge
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: web
    spec:
      containers:
      - name: web
        image: nginx:1.25
        ports:
        - containerPort: 80
        env:
        - name: BACKEND_URL
          valueFrom:
            configMapKeyRef:
              name: frontend-config
              key: BACKEND_URL
        - name: APP_NAME
          valueFrom:
            configMapKeyRef:
              name: frontend-config
              key: APP_NAME
EOF
    ok "Frontend deployed (missing ConfigMap)"

    # Problem 4: NetworkPolicy blocking DNS
    log "Problem 4: Applying NetworkPolicy blocking DNS..."
    kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-all
  namespace: challenge
spec:
  podSelector:
    matchLabels:
      tier: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 80
EOF
    ok "NetworkPolicy applied (blocks DNS)"

    sleep 10; echo ""; separator
    echo ""
    echo -e "  ${BOLD}What was deployed:${NC}"
    echo -e "    • A multi-tier app in namespace ${CYAN}challenge${NC}"
    echo -e "    • Backend (2 replicas) + Frontend (2 replicas) + Service + NetworkPolicy"
    echo ""
    echo -e "  ${RED}${BOLD}What's wrong:${NC}"
    echo -e "    • The entire application stack is broken — 4 different problems"
    echo -e "    • Nothing is working correctly"
    echo ""
    echo -e "  ${GREEN}${BOLD}Your task:${NC}"
    echo -e "    • Find and fix all 4 problems"
    echo -e "    • Start with: ${CYAN}kubectl get all -n challenge${NC}"
    echo -e "    • Use the DISCOVER framework to investigate systematically"
}

validate() {
    local errors=0
    info "Checking all 4 fixes..."; echo ""

    # Check 1: Backend pods running
    local backend_running; backend_running=$(kubectl get pods -n challenge -l app=backend --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    [[ "$backend_running" -ge 2 ]] && ok "Check 1: Backend pods Running ($backend_running/2)" || { err "Check 1: Backend not running ($backend_running/2)"; errors=$((errors+1)); }

    # Check 2: Service has endpoints
    local endpoints; endpoints=$(kubectl get endpoints backend-svc -n challenge -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    [[ -n "$endpoints" ]] && ok "Check 2: Service 'backend-svc' has endpoints" || { err "Check 2: Service has no endpoints"; errors=$((errors+1)); }

    # Check 3: Frontend pods running
    local frontend_running; frontend_running=$(kubectl get pods -n challenge -l app=frontend --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    [[ "$frontend_running" -ge 2 ]] && ok "Check 3: Frontend pods Running ($frontend_running/2)" || { err "Check 3: Frontend not running ($frontend_running/2)"; errors=$((errors+1)); }

    # Check 4: DNS works from frontend
    local frontend_pod; frontend_pod=$(kubectl get pods -n challenge -l app=frontend --no-headers 2>/dev/null | grep "Running" | head -1 | awk '{print $1}')
    if [[ -n "$frontend_pod" ]]; then
        local dns_result; dns_result=$(kubectl exec -n challenge "$frontend_pod" -- nslookup backend-svc.challenge 2>&1) || true
        echo "$dns_result" | grep -q "Address.*10\." && ok "Check 4: DNS works from frontend" || { err "Check 4: DNS still blocked"; errors=$((errors+1)); }
    else err "Check 4: No running frontend pod to test"; errors=$((errors+1)); fi

    echo ""
    [[ $errors -eq 0 ]] && { ok "All 4 checks passed!"; return 0; } || { err "$errors/4 checks failed."; return 1; }
}

hint() {
    local attempt="${1:-0}"; echo ""
    if [[ $attempt -lt 2 ]]; then info "Hint 1: Start by listing everything."; info "  kubectl get all -n challenge"; info "  kubectl get events -n challenge --sort-by='.lastTimestamp'"
    elif [[ $attempt -lt 4 ]]; then info "Hint 2: The 4 problems are:"; info "  1. Backend wrong image → ImagePullBackOff"; info "  2. Service selector mismatch"; info "  3. Frontend missing ConfigMap"; info "  4. NetworkPolicy blocks DNS"
    elif [[ $attempt -lt 6 ]]; then info "Hint 3: Fixes in order:"; info "  1. kubectl set image -n challenge deployment/backend api=nginx:1.25"; info "  2. kubectl patch svc backend-svc -n challenge -p '{selector:{app:backend}}'"; info "  3. Create ConfigMap 'frontend-config' with BACKEND_URL and APP_NAME"; info "  4. Edit NetworkPolicy to allow DNS port 53"
    else info "Hint 4: Specific commands:"; info "  kubectl set image -n challenge deploy/backend api=nginx:1.25"; info "  kubectl patch svc backend-svc -n challenge \\"; info "    -p '{\"spec\":{\"selector\":{\"app\":\"backend\"}}}'"; info "  kubectl create configmap frontend-config -n challenge \\"; info "    --from-literal=BACKEND_URL=http://backend-svc \\"; info "    --from-literal=APP_NAME=challenge-app"; info "  Edit netpol restrict-all to add egress port 53 UDP/TCP"; fi
}

solution() {
    echo ""; header "Solution"
    info "Fix 1: Correct the backend image"
    echo -e "  ${CYAN}kubectl set image -n challenge deployment/backend api=nginx:1.25${NC}"; echo ""
    info "Fix 2: Fix the Service selector"
    echo -e "  ${CYAN}kubectl patch svc backend-svc -n challenge \\\\${NC}"
    echo -e "  ${CYAN}  -p '{\"spec\":{\"selector\":{\"app\":\"backend\"}}}'${NC}"; echo ""
    info "Fix 3: Create the missing ConfigMap"
    echo -e "  ${CYAN}kubectl create configmap frontend-config -n challenge \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=BACKEND_URL=http://backend-svc \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=APP_NAME=challenge-app${NC}"
    echo -e "  ${CYAN}kubectl rollout restart deployment frontend -n challenge${NC}"; echo ""
    info "Fix 4: Add DNS to NetworkPolicy"
    cat <<'SOL'

  kubectl apply -f - <<EOF
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: restrict-all
    namespace: challenge
  spec:
    podSelector:
      matchLabels:
        tier: web
    policyTypes:
    - Egress
    egress:
    - ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
    - to:
      - podSelector:
          matchLabels:
            tier: api
      ports:
      - protocol: TCP
        port: 80
  EOF

SOL
    info "Problem 1: Image 'nginx:does-not-exist-tag' → nginx:1.25"
    info "Problem 2: Selector 'app: back-end' vs label 'app: backend'"
    info "Problem 3: ConfigMap 'frontend-config' didn't exist"
    info "Problem 4: NetworkPolicy blocked DNS (port 53)"
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
