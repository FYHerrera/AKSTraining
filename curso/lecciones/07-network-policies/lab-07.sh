#!/usr/bin/env bash
###############################################################################
# Lab 07 – Blocked Traffic  (STANDALONE)
#
# Scenario : A NetworkPolicy blocks DNS egress, breaking all connectivity.
# Objective: Fix the NetworkPolicy to allow DNS while keeping restrictions.
#
# Usage:  chmod +x lab-07.sh && ./lab-07.sh
###############################################################################

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

DEFAULT_REGION="${AKS_LAB_REGION:-canadacentral}"
DEFAULT_NODE_COUNT="${AKS_LAB_NODE_COUNT:-2}"
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
# Lab 07 – Blocked Traffic
###############################################################################
LAB_NAME="network-policies"
LAB_TITLE="Lab 07 – Blocked Traffic"
LAB_DESC="
  ${BOLD}Scenario${NC}
  The security team applied a NetworkPolicy in the ${CYAN}app${NC} namespace
  to restrict egress traffic. However, it accidentally blocks DNS,
  so pods can't resolve any service names.

  ${BOLD}Objective${NC}
  Fix the NetworkPolicy ${CYAN}restrict-egress${NC} in namespace ${CYAN}app${NC}
  so that:
    1. DNS resolution works (port 53 UDP/TCP)
    2. The pod can reach ${CYAN}web-svc${NC} in the same namespace

  ${BOLD}Useful commands${NC}
    kubectl get networkpolicy -n app
    kubectl describe netpol restrict-egress -n app
    kubectl exec -n app client -- nslookup web-svc.app
"

deploy() {
    create_aks_cluster "$LAB_NAME" "--network-policy azure"
    header "Injecting Lab Scenario"

    kubectl create namespace app 2>/dev/null || true

    log "Deploying web backend in app namespace..."
    kubectl run web --image=nginx:1.25 --labels="app=web,role=backend" -n app 2>/dev/null || true
    kubectl expose pod web --port=80 --name=web-svc -n app 2>/dev/null || true
    kubectl wait --for=condition=Ready pod/web -n app --timeout=120s &>/dev/null
    ok "Web backend and service ready"

    log "Deploying client pod..."
    kubectl run client --image=busybox:1.36 --restart=Never -n app --labels="app=client,role=frontend" -- sh -c "sleep 3600" 2>/dev/null || true
    kubectl wait --for=condition=Ready pod/client -n app --timeout=120s &>/dev/null
    ok "Client pod ready"

    log "Applying restrictive NetworkPolicy..."
    kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-egress
  namespace: app
spec:
  podSelector:
    matchLabels:
      role: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          role: backend
    ports:
    - protocol: TCP
      port: 80
EOF
    ok "NetworkPolicy applied"
    sleep 5

    echo ""; separator
    header "What was deployed"
    info "Namespace: app"
    info "Pod: web (nginx) with label role=backend, exposed as web-svc"
    info "Pod: client (busybox) with label role=frontend"
    info "NetworkPolicy: restrict-egress (targets role=frontend pods)"
    info "  Allows: egress to role=backend on port 80"
    info "  Blocks: everything else (including DNS)"

    echo ""; separator
    header "What's wrong"
    err "DNS is broken for frontend pods in 'app' namespace!"
    err "The client pod can't resolve any service names."

    echo ""; separator
    header "Your task"
    info "Fix the NetworkPolicy so DNS works AND HTTP to backend works."
    info "Test with: kubectl exec -n app client -- nslookup web-svc.app"
}

validate() {
    local dns_result; dns_result=$(kubectl exec -n app client -- nslookup web-svc.app 2>&1) || true
    if ! echo "$dns_result" | grep -q "Address.*10\."; then err "DNS resolution still failing."; return 1; fi
    ok "DNS resolution works"
    local http_result; http_result=$(kubectl exec -n app client -- wget -qO- http://web-svc --timeout=5 2>&1) || true
    if echo "$http_result" | grep -qi "nginx\|Welcome"; then ok "HTTP to web-svc works!"; return 0
    else err "Can't connect to web-svc via HTTP."; return 1; fi
}

hint() {
    local attempt="${1:-0}"; echo ""
    if [[ $attempt -lt 2 ]]; then info "Hint 1: Check what the NetworkPolicy allows."; info "  kubectl describe netpol restrict-egress -n app"; info "  Is DNS (port 53) allowed?"
    elif [[ $attempt -lt 4 ]]; then info "Hint 2: DNS uses UDP and TCP port 53."; info "  CoreDNS runs in kube-system."; info "  Add an egress rule for port 53."
    else info "Hint 3: Add DNS egress rule:"; info "  egress:"; info "  - ports:"; info "    - protocol: UDP"; info "      port: 53"; info "    - protocol: TCP"; info "      port: 53"; fi
}

solution() {
    echo ""; header "Solution"
    info "Add DNS egress rule to the NetworkPolicy:"
    cat <<'SOL'

  kubectl apply -f - <<EOF
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: restrict-egress
    namespace: app
  spec:
    podSelector:
      matchLabels:
        role: frontend
    policyTypes:
    - Egress
    egress:
    # Allow DNS
    - ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
    # Allow HTTP to backend
    - to:
      - podSelector:
          matchLabels:
            role: backend
      ports:
      - protocol: TCP
        port: 80
  EOF

SOL
    info "The original policy blocked DNS (port 53)."
    info "Adding port 53 UDP/TCP restores DNS resolution."
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
