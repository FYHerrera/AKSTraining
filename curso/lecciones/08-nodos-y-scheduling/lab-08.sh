#!/usr/bin/env bash
###############################################################################
# Lab 08 – Node Taint Issue  (STANDALONE)
#
# Scenario : All nodes have been tainted with NoSchedule, preventing any
#            new pods from being scheduled.
# Objective: Remove the taint or add tolerations so pods can run.
#
# Usage:  chmod +x lab-08.sh && ./lab-08.sh
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
# Lab 08 – Node Taint Issue
###############################################################################
LAB_NAME="nodes-scheduling"
LAB_TITLE="Lab 08 – Node Taint Issue"
LAB_DESC="
  ${BOLD}Scenario${NC}
  During maintenance, an operator tainted all nodes with
  ${RED}maintenance=true:NoSchedule${NC}. The maintenance is done but they
  forgot to remove the taint. New pods are stuck in ${RED}Pending${NC}.

  ${BOLD}Objective${NC}
  Get the deployment ${CYAN}web-app${NC} (3 replicas) to ${GREEN}Running${NC}.

  ${BOLD}Useful commands${NC}
    kubectl get pods
    kubectl describe pod <name>
    kubectl describe node <name>
    kubectl taint --help
"

deploy() {
    create_aks_cluster "$LAB_NAME"
    header "Injecting Lab Scenario"

    log "Applying maintenance taint to all nodes..."
    kubectl taint nodes --all maintenance=true:NoSchedule --overwrite 2>/dev/null || true
    ok "All nodes tainted with maintenance=true:NoSchedule"

    log "Deploying web-app..."
    kubectl apply -f - <<'EOF'
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
EOF
    ok "Deployment created"
    sleep 10; echo ""; separator
    echo ""
    echo -e "  ${BOLD}What was deployed:${NC}"
    echo -e "    • A web-app Deployment with 3 replicas (nginx:1.25)"
    echo ""
    echo -e "  ${RED}${BOLD}What's wrong:${NC}"
    echo -e "    • All 3 pods are stuck in Pending — none can be scheduled"
    echo ""
    echo -e "  ${GREEN}${BOLD}Your task:${NC}"
    echo -e "    • Investigate why pods can't be scheduled to any node"
    echo -e "    • Start with: ${CYAN}kubectl get pods${NC}"
    echo -e "    • Then: ${CYAN}kubectl describe pod <pod-name>${NC} → check Events"
}

validate() {
    local running; running=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$running" -ge 3 ]]; then ok "All 3 replicas are Running!"; return 0
    else err "$running/3 replicas running."
        local pending; pending=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep -c "Pending" || echo 0)
        [[ "$pending" -gt 0 ]] && info "$pending pods still Pending (check node taints)"; return 1; fi
}

hint() {
    local attempt="${1:-0}"; echo ""
    if [[ $attempt -lt 2 ]]; then info "Hint 1: Check Events in 'kubectl describe pod <name>'"; info "  Look for taint/toleration messages."
    elif [[ $attempt -lt 4 ]]; then info "Hint 2: All nodes have 'maintenance=true:NoSchedule' taint."; info "  kubectl describe node <name> | grep -A5 Taints"; info "  Remove the taint or add a toleration."
    else info "Hint 3: kubectl taint nodes --all maintenance=true:NoSchedule-"; info "  (Note the trailing dash '-')"; fi
}

solution() {
    echo ""; header "Solution"
    info "Option A – Remove taint (maintenance is over):"
    echo -e "  ${CYAN}kubectl taint nodes --all maintenance=true:NoSchedule-${NC}"; echo ""
    info "Option B – Add toleration to deployment:"
    echo -e "  ${CYAN}kubectl edit deployment web-app${NC}"
    info "  Add under spec.template.spec:"
    info "    tolerations:"
    info "    - key: \"maintenance\""
    info "      operator: \"Equal\""
    info "      value: \"true\""
    info "      effect: \"NoSchedule\""
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
