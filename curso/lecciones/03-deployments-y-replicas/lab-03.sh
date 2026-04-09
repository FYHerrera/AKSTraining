#!/usr/bin/env bash
###############################################################################
# Lab 03 – Failed Rollout  (STANDALONE)
#
# Scenario : A deployment update introduced a bad liveness probe that
#            causes CrashLoopBackOff. Fix or rollback.
# Objective: Get the deployment healthy with all replicas Running.
#
# Usage:  chmod +x lab-03.sh && ./lab-03.sh
###############################################################################

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
DEFAULT_REGION="${AKS_LAB_REGION:-canadacentral}"
DEFAULT_NODE_COUNT="${AKS_LAB_NODE_COUNT:-2}"
DEFAULT_VM_SIZE="${AKS_LAB_VM_SIZE:-Standard_D8ds_v5}"
K8S_VERSION=""

# ── State ────────────────────────────────────────────────────────────────────
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
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -ne "${BOLD}  Register missing providers? (y/n): ${NC}"; read -r ans
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

verify_cluster_health() {
    log "Verifying cluster health..."; kubectl wait --for=condition=Ready nodes --all --timeout=300s &>/dev/null || warn "Some nodes not ready"
    local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '/Ready/{n++} END{print n+0}'); ok "$ready/$DEFAULT_NODE_COUNT nodes Ready"
    local tries=0; while [[ $tries -lt 12 ]]; do local bad; bad=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '!/Running|Completed/{n++} END{print n+0}'); [[ "$bad" -eq 0 ]] && break; tries=$((tries+1)); sleep 10; done; ok "System pods healthy"
}

cleanup_resources() { echo ""; separator; echo -ne "${YELLOW}  Delete all lab resources? (y/n): ${NC}"; read -r response; if [[ "${response,,}" =~ ^y ]]; then log "Deleting resource group $RESOURCE_GROUP..."; az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true; ok "Deletion initiated."; else warn "Resources kept."; warn "Delete later: az group delete --name $RESOURCE_GROUP --yes"; fi; }

interactive_menu() {
    local validate_fn="$1" hint_fn="$2" solution_fn="$3"; local attempt=0
    while true; do
        echo ""; separator; echo -e "${BOLD}  Lab Menu${NC}"; separator
        echo -e "    ${GREEN}[V]${NC}  Validate my fix"; echo -e "    ${YELLOW}[H]${NC}  Request a hint"; echo -e "    ${CYAN}[S]${NC}  Show solution"; echo -e "    ${RED}[Q]${NC}  Quit & Cleanup"
        echo ""; echo -ne "${BOLD}  Choose an option: ${NC}"; read -r choice
        case "${choice,,}" in
            v|validate) attempt=$((attempt+1)); info "Validation attempt #$attempt"; if $validate_fn; then echo ""; header "Lab Completed Successfully!"; local end elapsed mins secs; end=$(date +%s); elapsed=$((end - LAB_START_TIME)); mins=$((elapsed / 60)); secs=$((elapsed % 60)); ok "Time: ${mins}m ${secs}s  |  Attempts: $attempt"; cleanup_resources; return 0; fi ;;
            h|hint) $hint_fn "$attempt" ;; s|solution) echo -ne "${YELLOW}  Show full solution? (y/n): ${NC}"; read -r c; [[ "${c,,}" =~ ^y ]] && $solution_fn ;;
            q|quit) cleanup_resources; return 1 ;; *) warn "Invalid choice. Use V, H, S or Q." ;; esac
    done
}

run_lab() { local lab_name="$1" lab_title="$2" lab_desc="$3" deploy_fn="$4" validate_fn="$5" hint_fn="$6" solution_fn="$7"; LAB_START_TIME=$(date +%s); init_logging "$lab_name"; header "$lab_title"; echo -e "$lab_desc"; echo ""; check_prerequisites; $deploy_fn; interactive_menu "$validate_fn" "$hint_fn" "$solution_fn"; }

###############################################################################
# Lab 03 – Failed Rollout
###############################################################################
LAB_NAME="deploy-replica"
LAB_TITLE="Lab 03 – Failed Rollout"
LAB_DESC="
  ${BOLD}Scenario${NC}
  An engineer updated the ${CYAN}api-server${NC} deployment with a new
  liveness probe, but the probe configuration is wrong.
  New pods are in ${RED}CrashLoopBackOff${NC} while old pods were scaled down.

  ${BOLD}Objective${NC}
  Get the ${CYAN}api-server${NC} deployment healthy with 3 Running replicas.

  ${BOLD}Useful commands${NC}
    kubectl get pods
    kubectl describe pod <name>
    kubectl rollout status deployment/api-server
    kubectl rollout history deployment/api-server
    kubectl rollout undo deployment/api-server
"

deploy() {
    create_aks_cluster "$LAB_NAME"
    header "Injecting Lab Scenario"

    log "Deploying initial api-server (working)..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: default
  annotations:
    kubernetes.io/change-cause: "initial deployment v1"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: api
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF
    kubectl rollout status deployment/api-server --timeout=120s &>/dev/null
    ok "Initial deployment running"

    log "Pushing broken update (bad liveness probe)..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: default
  annotations:
    kubernetes.io/change-cause: "added health check - v2"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: api
        image: nginx:1.25
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /healthz
            port: 9999
          initialDelaySeconds: 3
          periodSeconds: 5
          failureThreshold: 2
EOF
    ok "Broken update applied"
    sleep 15; echo ""; separator
    err "Deployment 'api-server' rollout is failing!"
    info "New pods are crashing due to a bad liveness probe."
    info "Try: kubectl rollout status deployment/api-server"
}

validate() {
    local running; running=$(kubectl get pods -l app=api-server --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    local restarts; restarts=$(kubectl get pods -l app=api-server --no-headers 2>/dev/null | awk '{print $4}' | sort -n | tail -1 || echo "0")
    if [[ "$running" -ge 3 ]] && [[ "$restarts" -lt 3 ]]; then ok "All 3 replicas are healthy!"; return 0
    else err "$running/3 running, highest restart count: $restarts"; return 1; fi
}

hint() {
    local attempt="${1:-0}"; echo ""
    if [[ $attempt -lt 2 ]]; then info "Hint 1: Check 'kubectl describe pod <crashing-pod>' → Events"; info "  Look at what is killing the container."
    elif [[ $attempt -lt 4 ]]; then info "Hint 2: The liveness probe targets port 9999 but nginx listens on 80."; info "  Options: fix the probe, remove it, or rollback."
    else info "Hint 3: Quickest fix: kubectl rollout undo deployment/api-server"; info "  Or fix probe: kubectl edit deployment api-server"; info "  Change port 9999 → 80 and path /healthz → /"; fi
}

solution() {
    echo ""; header "Solution"
    info "Option A – Rollback:"; echo -e "  ${CYAN}kubectl rollout undo deployment/api-server${NC}"; echo ""
    info "Option B – Fix the probe:"; echo -e "  ${CYAN}kubectl edit deployment api-server${NC}"
    info "  Change: port: 9999 → port: 80"; info "  Change: path: /healthz → path: /"; echo ""
    info "Explanation: nginx doesn't listen on 9999 or serve /healthz."
    info "The liveness probe fails → kubelet restarts → CrashLoopBackOff."
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
