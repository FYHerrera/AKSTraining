#!/usr/bin/env bash
###############################################################################
# Lab 01 – Application Down  (STANDALONE)
#
# Scenario : A web application service has no endpoints and is not responding.
#            The deployment exists but something is wrong with its replicas.
# Objective: Use kubectl to diagnose and restore the application.
#
# Usage:  chmod +x lab-01.sh && ./lab-01.sh
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

init_logging() {
    local lab_name="$1"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOG_DIR="${HOME}/aks-lab-logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/${lab_name}-$(date '+%Y%m%d-%H%M%S').log"
    log_to_file "=== Lab session started: $lab_name ==="
}

cleanup_on_interrupt() {
    echo ""; warn "Interrupted by user (Ctrl+C)"
    [[ -n "${RESOURCE_GROUP:-}" ]] && cleanup_resources
    exit 130
}
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
    for p in "${required_providers[@]}"; do
        local state; state=$(az provider show --namespace "$p" --query "registrationState" -o tsv 2>/dev/null || echo "")
        [[ "$state" == "Registered" ]] && ok "$p registered" || { err "$p NOT registered"; missing+=("$p"); }
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -ne "${BOLD}  Register missing providers? (y/n): ${NC}"; read -r ans
        if [[ "${ans,,}" =~ ^y ]]; then
            for p in "${missing[@]}"; do az provider register --namespace "$p" -o none; done
            for p in "${missing[@]}"; do
                local w=0; while [[ "$(az provider show --namespace "$p" --query 'registrationState' -o tsv 2>/dev/null)" != "Registered" ]]; do
                    ((w++)); [[ $w -ge 30 ]] && { err "Timeout for $p"; exit 1; }; sleep 10; done; ok "$p registered"
            done
        else err "Cannot proceed without providers."; exit 1; fi
    fi
    echo ""; info "All pre-flight checks passed!"; echo ""
}

get_latest_k8s_version() {
    local region="${1:-$DEFAULT_REGION}"
    K8S_VERSION=$(az aks get-versions --location "$region" --query "values[?isDefault].version" -o tsv 2>/dev/null || echo "")
    if [[ -z "$K8S_VERSION" ]]; then K8S_VERSION="1.29"; warn "Defaulting to K8s $K8S_VERSION"; fi
}

create_aks_cluster() {
    local scenario="$1"
    CLUSTER_NAME="aks-training"; RESOURCE_GROUP="aks-training-rg"
    header "Lab Environment Setup"
    info "Resource Group : $RESOURCE_GROUP"; info "Cluster Name   : $CLUSTER_NAME"; info "Region         : $DEFAULT_REGION"
    # Check if cluster already exists
    local cluster_state=""
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        cluster_state=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "provisioningState" -o tsv 2>/dev/null || echo "")
    fi
    if [[ "$cluster_state" == "Succeeded" ]]; then
        ok "Cluster already exists and is Running — reusing it"
        log "Fetching credentials..."; az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing; ok "kubectl configured"
        MC_RESOURCE_GROUP=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "nodeResourceGroup" -o tsv 2>/dev/null || echo "")
        log "Cleaning previous lab resources..."
        kubectl delete all --all -n default --wait=false 2>/dev/null || true
        kubectl delete configmap,secret,pvc,networkpolicy --all -n default 2>/dev/null || true
        for ns in production staging; do kubectl delete ns "$ns" --wait=false 2>/dev/null || true; done
        ok "Previous resources cleaned"
        verify_cluster_health; return 0
    fi
    if [[ "$cluster_state" == "Creating" ]] || [[ "$cluster_state" == "Updating" ]]; then
        warn "Cluster is in '$cluster_state' state — waiting for it to be ready..."
        az aks wait -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --created --timeout 600 2>/dev/null || true
        ok "Cluster is ready"
        log "Fetching credentials..."; az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing; ok "kubectl configured"
        MC_RESOURCE_GROUP=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "nodeResourceGroup" -o tsv 2>/dev/null || echo "")
        verify_cluster_health; return 0
    fi
    if [[ -n "$cluster_state" ]]; then
        warn "Cluster is in '$cluster_state' state — cleaning up before recreating..."
        az aks delete -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --yes 2>/dev/null || true
    fi
    # Cluster doesn't exist — create fresh
    info "Node Count     : $DEFAULT_NODE_COUNT"; info "VM Size        : $DEFAULT_VM_SIZE"; echo ""
    log "Creating resource group..."; az group create --name "$RESOURCE_GROUP" --location "$DEFAULT_REGION" -o none; ok "Resource group created"
    get_latest_k8s_version "$DEFAULT_REGION"; info "Kubernetes version: $K8S_VERSION"
    log "Creating AKS cluster (5-10 min)..."
    az aks create --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --node-count "$DEFAULT_NODE_COUNT" --node-vm-size "$DEFAULT_VM_SIZE" --kubernetes-version "$K8S_VERSION" --location "$DEFAULT_REGION" --generate-ssh-keys --network-plugin azure -o none
    ok "AKS cluster created"
    log "Fetching credentials..."; az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing; ok "kubectl configured"
    MC_RESOURCE_GROUP=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query "nodeResourceGroup" -o tsv 2>/dev/null || echo "")
    verify_cluster_health
}

verify_cluster_health() {
    log "Verifying cluster health..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s &>/dev/null || warn "Some nodes not ready"
    local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '/Ready/{n++} END{print n+0}')
    ok "$ready/$DEFAULT_NODE_COUNT nodes Ready"
    local tries=0; while [[ $tries -lt 12 ]]; do
        local bad; bad=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '!/Running|Completed/{n++} END{print n+0}')
        [[ "$bad" -eq 0 ]] && break; tries=$((tries+1)); sleep 10; done; ok "System pods healthy"
}

cleanup_resources() {
    echo ""; separator
    echo -e "${BOLD}  Cleanup Options:${NC}"
    echo -e "    ${GREEN}[K]${NC}  Clean Kubernetes resources only (keep cluster for next lab)"
    echo -e "    ${RED}[D]${NC}  Delete everything (resource group + cluster)"
    echo -e "    ${CYAN}[S]${NC}  Skip cleanup"
    echo ""; echo -ne "${BOLD}  Choose an option: ${NC}"; read -r response
    case "${response,,}" in
        k) log "Cleaning Kubernetes resources..."
           kubectl delete all --all -n default --wait=false 2>/dev/null || true
           kubectl delete configmap,secret,pvc,networkpolicy --all -n default 2>/dev/null || true
           for ns in production staging; do kubectl delete ns "$ns" --wait=false 2>/dev/null || true; done
           ok "Kubernetes resources cleaned. Cluster kept for next lab." ;;
        d) log "Deleting resource group $RESOURCE_GROUP..."
           az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
           ok "Deletion initiated." ;;
        *) warn "Resources kept."; warn "Delete later: az group delete --name $RESOURCE_GROUP --yes" ;;
    esac
}

show_connect_info() {
    echo ""; separator
    header "Open a new Cloud Shell tab to work on the lab"
    info "Click this link to open a new Cloud Shell session:"
    echo -e "  ${CYAN}https://shell.azure.com/bash${NC}"
    echo ""
    info "Then run this command to connect to the cluster:"
    echo -e "  ${GREEN}az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing${NC}"
    echo ""
}

interactive_menu() {
    local validate_fn="$1" hint_fn="$2" solution_fn="$3"; local attempt=0
    while true; do
        echo ""; separator; echo -e "${BOLD}  Lab Menu${NC}"; separator
        echo -e "    ${GREEN}[V]${NC}  Validate my fix"; echo -e "    ${YELLOW}[H]${NC}  Request a hint"
        echo -e "    ${CYAN}[S]${NC}  Show solution"; echo -e "    ${BLUE}[C]${NC}  Connect to cluster (new tab)"
        echo -e "    ${RED}[Q]${NC}  Quit & Cleanup"
        echo ""; echo -ne "${BOLD}  Choose an option: ${NC}"; read -r choice
        case "${choice,,}" in
            v|validate) attempt=$((attempt+1)); info "Validation attempt #$attempt"
                if $validate_fn; then echo ""; header "Lab Completed Successfully!"
                    local end elapsed mins secs; end=$(date +%s); elapsed=$((end - LAB_START_TIME)); mins=$((elapsed / 60)); secs=$((elapsed % 60))
                    ok "Time: ${mins}m ${secs}s  |  Attempts: $attempt"; cleanup_resources; return 0; fi ;;
            h|hint) $hint_fn "$attempt" ;;
            s|solution) echo -ne "${YELLOW}  Show full solution? (y/n): ${NC}"; read -r c; [[ "${c,,}" =~ ^y ]] && $solution_fn ;;
            c|connect) show_connect_info ;;
            q|quit) cleanup_resources; return 1 ;;
            *) warn "Invalid choice. Use V, H, S, C or Q." ;; esac
    done
}

run_lab() {
    local lab_name="$1" lab_title="$2" lab_desc="$3"
    local deploy_fn="$4" validate_fn="$5" hint_fn="$6" solution_fn="$7"
    LAB_START_TIME=$(date +%s); init_logging "$lab_name"
    header "$lab_title"; echo -e "$lab_desc"; echo ""
    check_prerequisites; $deploy_fn
    show_connect_info
    interactive_menu "$validate_fn" "$hint_fn" "$solution_fn"
}

###############################################################################
# Lab 01 – Application Down + Scavenger Hunt
###############################################################################
LAB_NAME="kubectl-fund"
LAB_TITLE="Lab 01 – Application Down + Scavenger Hunt"
LAB_DESC="
  ${BOLD}Part A – Application Down${NC}
  The operations team reports that the ${RED}web-app${NC} service is NOT
  responding — users see connection timeouts.
  The ${CYAN}web-app${NC} Service exists in the ${CYAN}default${NC} namespace, but it has
  ${RED}0 endpoints${NC}. Other workloads appear to be running normally.
  Use ${CYAN}kubectl${NC} to investigate and fix the application.

  ${BOLD}Part B – Scavenger Hunt${NC}
  A ConfigMap named ${CYAN}scavenger-answers${NC} already exists in the
  ${CYAN}default${NC} namespace with ${RED}placeholder values${NC}.
  Update it with the correct answers by exploring the cluster:
    ${GREEN}node-count${NC}  = number of nodes (e.g. \"2\")
    ${GREEN}dns-pod${NC}     = full name of a CoreDNS pod in kube-system
    ${GREEN}k8s-version${NC} = kubelet version on a node (e.g. \"v1.29.7\")
"

deploy() {
    create_aks_cluster "$LAB_NAME"
    header "Injecting Lab Scenario"
    log "Deploying multi-tier application..."

    # Create healthy workloads in multiple namespaces
    kubectl create namespace production 2>/dev/null || true
    kubectl create namespace staging 2>/dev/null || true
    kubectl run metrics-collector --image=nginx:1.25 -n production --labels="app=metrics,tier=monitoring" 2>/dev/null || true
    kubectl run staging-app --image=nginx:1.25 -n staging --labels="app=staging-app" 2>/dev/null || true
    kubectl run debug-tools --image=busybox:1.36 --restart=Never -- sh -c "sleep 3600" 2>/dev/null || true

    # Create the web-app deployment (3 replicas) then scale to 0
    kubectl create deployment web-app --image=nginx:1.25 --replicas=3 2>/dev/null || true
    kubectl expose deployment web-app --port=80 --target-port=80 --type=ClusterIP 2>/dev/null || true
    kubectl wait --for=condition=Available deployment/web-app --timeout=120s &>/dev/null || true
    # Inject the failure: scale to 0
    kubectl scale deployment web-app --replicas=0 2>/dev/null || true
    sleep 5

    # Create a healthy backend deployment
    kubectl create deployment api-backend --image=nginx:1.25 --replicas=2 2>/dev/null || true
    kubectl expose deployment api-backend --port=8080 --target-port=80 --type=ClusterIP 2>/dev/null || true
    kubectl wait --for=condition=Available deployment/api-backend --timeout=120s &>/dev/null || true

    # Pre-create scavenger ConfigMap with placeholder values
    kubectl create configmap scavenger-answers \
        --from-literal=node-count=REPLACE_ME \
        --from-literal=dns-pod=REPLACE_ME \
        --from-literal=k8s-version=REPLACE_ME 2>/dev/null || true

    kubectl wait --for=condition=Ready pod --all -n production --timeout=120s &>/dev/null || true
    kubectl wait --for=condition=Ready pod --all -n staging --timeout=120s &>/dev/null || true
    kubectl wait --for=condition=Ready pod/debug-tools --timeout=120s &>/dev/null || true

    ok "Application environment deployed"

    echo ""; separator
    header "What was deployed"
    info "Namespaces: default, production, staging"
    info "Deployments: web-app (default), api-backend (default)"
    info "Services: web-app (ClusterIP:80), api-backend (ClusterIP:8080)"
    info "Pods: metrics-collector (production), staging-app (staging), debug-tools (default)"
    info "ConfigMap: scavenger-answers (default) — has placeholder values"

    echo ""; separator
    header "What's wrong"
    err "ALERT: The web-app service is NOT responding!"
    err "Endpoints show 0 backends for the web-app service."
    info "Other services (api-backend, production, staging) appear healthy."

    echo ""; separator
    header "Your task"
    info "Part A: Investigate why web-app has 0 endpoints and fix it."
    info "Part B: The ConfigMap 'scavenger-answers' exists with REPLACE_ME values."
    info "        Update them with the real values using:"
    echo -e "  ${CYAN}kubectl edit configmap scavenger-answers${NC}"
    info "        Or delete and recreate with --from-literal flags."
}

validate() {
    local errors=0

    # ── Part A: web-app must be running ──
    header "Part A – Application Fix"
    local ready; ready=$(kubectl get deployment web-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ -z "$ready" || "$ready" == "0" ]]; then
        err "web-app deployment has 0 ready replicas."
        errors=$((errors+1))
    else
        ok "web-app deployment has $ready ready replica(s)"
    fi
    local endpoints; endpoints=$(kubectl get endpoints web-app -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    if [[ -z "$endpoints" ]]; then
        err "web-app service still has no endpoints."
        errors=$((errors+1))
    else
        ok "web-app service has active endpoints"
    fi
    local running; running=$(kubectl get pods -l app=web-app --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$running" -gt 0 ]]; then
        ok "$running web-app pod(s) Running"
    else
        err "No web-app pods in Running state."
        errors=$((errors+1))
    fi

    # ── Part B: scavenger hunt ConfigMap ──
    header "Part B – Scavenger Hunt"
    if ! kubectl get configmap scavenger-answers &>/dev/null; then
        err "ConfigMap 'scavenger-answers' not found."
        errors=$((errors+1))
    else
        ok "ConfigMap 'scavenger-answers' found"
        local actual_nodes expected_nodes
        actual_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        expected_nodes=$(kubectl get configmap scavenger-answers -o jsonpath='{.data.node-count}' 2>/dev/null || echo "")
        [[ "$expected_nodes" == "$actual_nodes" ]] && ok "node-count correct ($actual_nodes)" || { err "node-count wrong ('$expected_nodes', actual '$actual_nodes')"; errors=$((errors+1)); }
        local dns_pod_answer; dns_pod_answer=$(kubectl get configmap scavenger-answers -o jsonpath='{.data.dns-pod}' 2>/dev/null || echo "")
        kubectl get pod "$dns_pod_answer" -n kube-system &>/dev/null && ok "dns-pod correct ($dns_pod_answer)" || { err "dns-pod '$dns_pod_answer' not found in kube-system"; errors=$((errors+1)); }
        local k8s_answer actual_version
        k8s_answer=$(kubectl get configmap scavenger-answers -o jsonpath='{.data.k8s-version}' 2>/dev/null || echo "")
        actual_version=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null || echo "")
        [[ "$k8s_answer" == "$actual_version" ]] && ok "k8s-version correct ($k8s_answer)" || { err "k8s-version wrong ('$k8s_answer', actual '$actual_version')"; errors=$((errors+1)); }
    fi

    [[ $errors -eq 0 ]]
}

hint() {
    local attempt="${1:-0}"; echo ""
    if [[ $attempt -lt 2 ]]; then
        info "Hint 1 (Part A): List everything in the default namespace."
        info "  kubectl get all"
        info "  Pay close attention to the READY column on deployments."
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2 (Part A): Inspect the web-app deployment."
        info "  kubectl describe deployment web-app"
        info "  kubectl get endpoints web-app"
        info "  How many replicas does the deployment spec request?"
    elif [[ $attempt -lt 6 ]]; then
        info "Hint 3 (Part A): The deployment has 0 replicas configured."
        info "  kubectl scale --help"
        echo ""
        info "Hint (Part B): Use these to find scavenger answers:"
        info "  kubectl get nodes"
        info "  kubectl get pods -n kube-system"
        info "  kubectl get nodes -o wide   (VERSION column)"
    else
        info "Hint 4 (Part B): Update the ConfigMap (delete + recreate):"
        info "  kubectl delete configmap scavenger-answers"
        info "  kubectl create configmap scavenger-answers \\"
        info "    --from-literal=node-count=<N> \\"
        info "    --from-literal=dns-pod=<coredns-pod-name> \\"
        info "    --from-literal=k8s-version=<version>"
    fi
}

solution() {
    echo ""; header "Solution – Part A"
    info "Step 1: List all resources and spot the problem"
    echo -e "  ${CYAN}kubectl get all${NC}"
    echo -e "  ${CYAN}# Notice web-app shows 0/0 in READY column${NC}"; echo ""
    info "Step 2: Inspect the deployment"
    echo -e "  ${CYAN}kubectl describe deployment web-app${NC}"
    echo -e "  ${CYAN}# Shows 'Replicas: 0 desired | 0 updated | 0 total'${NC}"; echo ""
    info "Step 3: Scale the deployment back up"
    echo -e "  ${CYAN}kubectl scale deployment web-app --replicas=3${NC}"; echo ""
    info "Step 4: Verify the fix"
    echo -e "  ${CYAN}kubectl get deployment web-app${NC}"
    echo -e "  ${CYAN}kubectl get endpoints web-app${NC}"

    echo ""; header "Solution – Part B"
    info "Step 5: Get the node count"
    echo -e "  ${CYAN}kubectl get nodes --no-headers | wc -l${NC}"; echo ""
    info "Step 6: Get a CoreDNS pod name"
    echo -e "  ${CYAN}kubectl get pods -n kube-system -l k8s-app=kube-dns${NC}"; echo ""
    info "Step 7: Get the Kubernetes version"
    echo -e "  ${CYAN}kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'${NC}"; echo ""
    info "Step 8: Update the ConfigMap (delete + recreate)"
    echo -e "  ${CYAN}kubectl delete configmap scavenger-answers${NC}"
    echo -e "  ${CYAN}kubectl create configmap scavenger-answers \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=node-count=\$(kubectl get nodes --no-headers | wc -l) \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=dns-pod=\$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name | head -1 | cut -d/ -f2) \\\\${NC}"
    echo -e "  ${CYAN}  --from-literal=k8s-version=\$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')${NC}"
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
