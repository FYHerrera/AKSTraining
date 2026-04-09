#!/usr/bin/env bash
###############################################################################
# Lab 05 – Missing Configuration  (STANDALONE)
#
# Scenario : An app expects a ConfigMap and a Secret that don't exist.
# Objective: Create the missing ConfigMap and Secret so the app runs.
#
# Usage:  chmod +x lab-05.sh && ./lab-05.sh
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

verify_cluster_health() { log "Verifying cluster health..."; kubectl wait --for=condition=Ready nodes --all --timeout=300s &>/dev/null || warn "Some nodes not ready"; local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0); ok "$ready/$DEFAULT_NODE_COUNT nodes Ready"; local tries=0; while [[ $tries -lt 12 ]]; do local bad; bad=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l || echo 0); [[ "$bad" -eq 0 ]] && break; ((tries++)); sleep 10; done; ok "System pods healthy"; }
cleanup_resources() { echo ""; separator; echo -ne "${YELLOW}  Delete all lab resources? (y/n): ${NC}"; read -r response; if [[ "${response,,}" =~ ^y ]]; then log "Deleting resource group $RESOURCE_GROUP..."; az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true; ok "Deletion initiated."; else warn "Resources kept."; warn "Delete later: az group delete --name $RESOURCE_GROUP --yes"; fi; }

interactive_menu() {
    local validate_fn="$1" hint_fn="$2" solution_fn="$3"; local attempt=0
    while true; do echo ""; separator; echo -e "${BOLD}  Lab Menu${NC}"; separator; echo -e "    ${GREEN}[V]${NC}  Validate my fix"; echo -e "    ${YELLOW}[H]${NC}  Request a hint"; echo -e "    ${CYAN}[S]${NC}  Show solution"; echo -e "    ${RED}[Q]${NC}  Quit & Cleanup"; echo ""; echo -ne "${BOLD}  Choose an option: ${NC}"; read -r choice
        case "${choice,,}" in v|validate) attempt=$((attempt+1)); info "Validation attempt #$attempt"; if $validate_fn; then echo ""; header "Lab Completed Successfully!"; local end elapsed mins secs; end=$(date +%s); elapsed=$((end - LAB_START_TIME)); mins=$((elapsed / 60)); secs=$((elapsed % 60)); ok "Time: ${mins}m ${secs}s  |  Attempts: $attempt"; cleanup_resources; return 0; fi ;; h|hint) $hint_fn "$attempt" ;; s|solution) echo -ne "${YELLOW}  Show full solution? (y/n): ${NC}"; read -r c; [[ "${c,,}" =~ ^y ]] && $solution_fn ;; q|quit) cleanup_resources; return 1 ;; *) warn "Invalid choice." ;; esac; done
}

run_lab() { local lab_name="$1" lab_title="$2" lab_desc="$3" deploy_fn="$4" validate_fn="$5" hint_fn="$6" solution_fn="$7"; LAB_START_TIME=$(date +%s); init_logging "$lab_name"; header "$lab_title"; echo -e "$lab_desc"; echo ""; check_prerequisites; $deploy_fn; interactive_menu "$validate_fn" "$hint_fn" "$solution_fn"; }

###############################################################################
# Lab 05 – Missing Configuration
###############################################################################
LAB_NAME="configmaps-secrets"
LAB_TITLE="Lab 05 – Missing Configuration"
LAB_DESC="
  ${BOLD}Scenario${NC}
  A deployment references a ConfigMap ${CYAN}app-config${NC} and a Secret
  ${CYAN}db-credentials${NC} that were never created. Pods are stuck in
  ${RED}CreateContainerConfigError${NC}.

  ${BOLD}Objective${NC}
  Create the missing ConfigMap and Secret so all 2 replicas are ${GREEN}Running${NC}.

  The app expects these environment variables:
    From ConfigMap ${CYAN}app-config${NC}:
      ${GREEN}APP_ENV${NC} = any value (e.g. \"production\")
      ${GREEN}LOG_LEVEL${NC} = any value (e.g. \"info\")
    From Secret ${CYAN}db-credentials${NC}:
      ${GREEN}DB_USER${NC} = any value
      ${GREEN}DB_PASS${NC} = any value

  ${BOLD}Useful commands${NC}
    kubectl get pods
    kubectl describe pod <name>
    kubectl create configmap --help
    kubectl create secret generic --help
"

deploy() {
    create_aks_cluster "$LAB_NAME"
    header "Injecting Lab Scenario"

    log "Deploying app that references missing config..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: config-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: config-app
  template:
    metadata:
      labels:
        app: config-app
    spec:
      containers:
      - name: app
        image: nginx:1.25
        ports:
        - containerPort: 80
        env:
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_ENV
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_USER
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_PASS
EOF
    ok "Deployment applied (pods will fail)"
    sleep 10; echo ""; separator
    err "Pods are in CreateContainerConfigError!"
    info "Try:  kubectl get pods"; info "Then: kubectl describe pod <pod-name>"
}

validate() {
    local running; running=$(kubectl get pods -l app=config-app --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$running" -ge 2 ]]; then
        local pod_name; pod_name=$(kubectl get pods -l app=config-app --no-headers 2>/dev/null | grep "Running" | head -1 | awk '{print $1}')
        local env_check; env_check=$(kubectl exec "$pod_name" -- env 2>/dev/null || echo "")
        if echo "$env_check" | grep -q "APP_ENV" && echo "$env_check" | grep -q "DB_USER"; then ok "All replicas Running with correct env vars!"; return 0
        else err "Pods running but env vars not set."; return 1; fi
    else err "$running/2 replicas running."; return 1; fi
}

hint() {
    local attempt="${1:-0}"; echo ""
    if [[ $attempt -lt 2 ]]; then info "Hint 1: Run 'kubectl describe pod <name>' → Events."; info "  It tells which ConfigMap or Secret is missing."
    elif [[ $attempt -lt 4 ]]; then info "Hint 2: Create both:"; info "  - ConfigMap 'app-config' with APP_ENV and LOG_LEVEL"; info "  - Secret 'db-credentials' with DB_USER and DB_PASS"
    else info "Hint 3:"; info "  kubectl create configmap app-config \\"; info "    --from-literal=APP_ENV=production --from-literal=LOG_LEVEL=info"; info "  kubectl create secret generic db-credentials \\"; info "    --from-literal=DB_USER=admin --from-literal=DB_PASS=secret123"; fi
}

solution() {
    echo ""; header "Solution"
    info "Step 1: Create the ConfigMap"
    echo -e "  ${CYAN}kubectl create configmap app-config \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=APP_ENV=production \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=LOG_LEVEL=info${NC}"; echo ""
    info "Step 2: Create the Secret"
    echo -e "  ${CYAN}kubectl create secret generic db-credentials \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=DB_USER=admin \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=DB_PASS=secret123${NC}"; echo ""
    info "Step 3: If pods don't auto-restart:"
    echo -e "  ${CYAN}kubectl rollout restart deployment config-app${NC}"
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
