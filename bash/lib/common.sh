#!/usr/bin/env bash
###############################################################################
# common.sh - Shared library for AKS Lab scripts
#
# Source this file at the top of every lab script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"
###############################################################################

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
DEFAULT_REGION="${AKS_LAB_REGION:-canadacentral}"
DEFAULT_NODE_COUNT="${AKS_LAB_NODE_COUNT:-1}"
DEFAULT_VM_SIZE="${AKS_LAB_VM_SIZE:-Standard_D8ds_v5}"
K8S_VERSION=""

# ── State ────────────────────────────────────────────────────────────────────
LOG_DIR=""
LOG_FILE=""
RESOURCE_GROUP=""
CLUSTER_NAME=""
MC_RESOURCE_GROUP=""
LAB_START_TIME=""

# ── Logging ──────────────────────────────────────────────────────────────────
log_to_file() {
    [[ -n "${LOG_FILE:-}" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log()    { echo -e "${NC}[$(date '+%H:%M:%S')] $1${NC}";           log_to_file "$1"; }
ok()     { echo -e "${GREEN}  [✓] $1${NC}";                        log_to_file "[OK] $1"; }
err()    { echo -e "${RED}  [✗] $1${NC}";                          log_to_file "[ERROR] $1"; }
warn()   { echo -e "${YELLOW}  [!] $1${NC}";                       log_to_file "[WARN] $1"; }
info()   { echo -e "${CYAN}  [i] $1${NC}";                         log_to_file "[INFO] $1"; }

header() {
    echo ""
    echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}    $1${NC}"
    echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"
    echo ""
}

separator() {
    echo -e "${BLUE}  ───────────────────────────────────────────────────────${NC}"
}

# ── Initialise logging ──────────────────────────────────────────────────────
init_logging() {
    local lab_name="$1"
    local caller_dir
    caller_dir="$(cd "$(dirname "${BASH_SOURCE[2]:-${BASH_SOURCE[1]}}")" && pwd)"
    LOG_DIR="${caller_dir}/../logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/${lab_name}-$(date '+%Y%m%d-%H%M%S').log"
    log_to_file "=== Lab session started: $lab_name ==="
}

# ── Trap – Ctrl+C handler ───────────────────────────────────────────────────
cleanup_on_interrupt() {
    echo ""
    warn "Interrupted by user (Ctrl+C)"
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        cleanup_resources
    fi
    exit 130
}
trap cleanup_on_interrupt INT TERM

# ── Name generator ───────────────────────────────────────────────────────────
generate_name() {
    local scenario="$1"
    local suffix
    suffix=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 4)
    echo "aks-lab-${scenario}-${suffix}"
}

# ── Pre-flight checks ───────────────────────────────────────────────────────
check_prerequisites() {
    header "Pre-flight Checks"

    # Azure CLI
    if ! command -v az &>/dev/null; then
        err "Azure CLI (az) is not installed."
        info "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi
    ok "Azure CLI found ($(az version --query '\"azure-cli\"' -o tsv 2>/dev/null))"

    # kubectl
    if ! command -v kubectl &>/dev/null; then
        warn "kubectl not found – installing via Azure CLI..."
        az aks install-cli 2>/dev/null || true
    fi
    if command -v kubectl &>/dev/null; then
        ok "kubectl found"
    else
        err "kubectl could not be installed. Please install it manually."
        exit 1
    fi

    # jq
    if ! command -v jq &>/dev/null; then
        err "jq is not installed. Install: https://jqlang.github.io/jq/download/"
        exit 1
    fi
    ok "jq found"

    # Azure login
    local account
    account=$(az account show -o json 2>/dev/null) || true
    if [[ -z "$account" ]]; then
        err "Not logged into Azure."
        info "Run:  az login"
        info "Then re-run this lab."
        exit 1
    fi
    local sub_name sub_id user_name
    sub_name=$(echo "$account" | jq -r '.name')
    sub_id=$(echo "$account" | jq -r '.id')
    user_name=$(echo "$account" | jq -r '.user.name')

    ok "Logged in as: ${user_name}"
    ok "Subscription: ${sub_name} (${sub_id})"

    # Required Azure resource providers
    local required_providers=(
        "Microsoft.ContainerService"
        "Microsoft.Network"
        "Microsoft.Compute"
        "Microsoft.Storage"
        "Microsoft.ManagedIdentity"
        "Microsoft.OperationsManagement"
        "Microsoft.OperationalInsights"
    )

    local missing_providers=()
    for provider in "${required_providers[@]}"; do
        local state
        state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "")
        if [[ "$state" == "Registered" ]]; then
            ok "$provider registered"
        else
            err "$provider NOT registered (state: ${state:-unknown})"
            missing_providers+=("$provider")
        fi
    done

    if [[ ${#missing_providers[@]} -gt 0 ]]; then
        echo ""
        warn "${#missing_providers[@]} provider(s) need registration:"
        for p in "${missing_providers[@]}"; do
            echo -e "    ${YELLOW}- $p${NC}"
        done
        echo ""
        echo -ne "${BOLD}  Register all missing providers now? (y/n): ${NC}"
        read -r register_choice
        if [[ "${register_choice,,}" =~ ^y ]]; then
            for p in "${missing_providers[@]}"; do
                log "Registering $p..."
                az provider register --namespace "$p" -o none
            done
            log "Waiting for all providers to register (may take 2-5 min)..."
            for p in "${missing_providers[@]}"; do
                local wait_count=0
                while [[ "$(az provider show --namespace "$p" --query 'registrationState' -o tsv 2>/dev/null)" != "Registered" ]]; do
                    ((wait_count++))
                    if [[ $wait_count -ge 30 ]]; then
                        err "Timeout waiting for $p. Try again later."
                        exit 1
                    fi
                    sleep 10
                done
                ok "$p registered"
            done
        else
            err "Cannot proceed without required providers."
            info "Register manually:"
            for p in "${missing_providers[@]}"; do
                echo -e "    ${CYAN}az provider register --namespace $p${NC}"
            done
            exit 1
        fi
    fi

    echo ""
    info "All pre-flight checks passed!"
    echo ""
}

# ── Get latest stable K8s version ───────────────────────────────────────────
get_latest_k8s_version() {
    local region="${1:-$DEFAULT_REGION}"
    K8S_VERSION=$(az aks get-versions --location "$region" \
        --query "values[?isDefault].version" -o tsv 2>/dev/null || echo "")
    if [[ -z "$K8S_VERSION" ]]; then
        K8S_VERSION="1.29"
        warn "Could not detect latest K8s version; defaulting to $K8S_VERSION"
    fi
}

# ── Create AKS cluster ──────────────────────────────────────────────────────
create_aks_cluster() {
    local scenario="$1"
    local extra_args="${2:-}"

    CLUSTER_NAME=$(generate_name "$scenario")
    RESOURCE_GROUP="${CLUSTER_NAME}-rg"

    header "Creating Lab Environment"
    info "Resource Group : $RESOURCE_GROUP"
    info "Cluster Name   : $CLUSTER_NAME"
    info "Region         : $DEFAULT_REGION"
    info "Node Count     : $DEFAULT_NODE_COUNT"
    info "VM Size        : $DEFAULT_VM_SIZE"
    echo ""

    # Resource group
    log "Creating resource group..."
    az group create --name "$RESOURCE_GROUP" --location "$DEFAULT_REGION" -o none
    ok "Resource group created"

    # K8s version
    get_latest_k8s_version "$DEFAULT_REGION"
    info "Kubernetes version: $K8S_VERSION"

    # AKS cluster
    log "Creating AKS cluster (this takes ~5-10 minutes)..."
    local cmd="az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --node-count $DEFAULT_NODE_COUNT \
        --node-vm-size $DEFAULT_VM_SIZE \
        --kubernetes-version $K8S_VERSION \
        --location $DEFAULT_REGION \
        --generate-ssh-keys \
        --network-plugin azure \
        -o none"

    [[ -n "$extra_args" ]] && cmd="$cmd $extra_args"
    eval "$cmd"
    ok "AKS cluster created"

    # Credentials
    log "Fetching cluster credentials..."
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
    ok "kubectl configured for $CLUSTER_NAME"

    # MC resource group
    MC_RESOURCE_GROUP=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" \
        --query "nodeResourceGroup" -o tsv 2>/dev/null || echo "")

    verify_cluster_health
}

# ── Verify cluster health ───────────────────────────────────────────────────
verify_cluster_health() {
    log "Verifying cluster health..."

    # Wait for nodes
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=300s &>/dev/null; then
        warn "Some nodes are not ready; continuing anyway."
    fi
    local ready
    ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
    ok "$ready/$DEFAULT_NODE_COUNT nodes Ready"

    # Wait for kube-system pods
    local tries=0
    while [[ $tries -lt 12 ]]; do
        local bad
        bad=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
            | grep -v "Running\|Completed" | wc -l || echo 0)
        [[ "$bad" -eq 0 ]] && break
        ((tries++))
        sleep 10
    done
    ok "System pods healthy"
}

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup_resources() {
    echo ""
    separator
    echo -ne "${YELLOW}  Delete all lab resources? (y/n): ${NC}"
    read -r response
    if [[ "${response,,}" =~ ^y ]]; then
        log "Deleting resource group $RESOURCE_GROUP (background)..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
        ok "Deletion initiated – may take a few minutes in the background."
    else
        warn "Resources kept."
        warn "Resource Group : $RESOURCE_GROUP"
        warn "Delete later   : az group delete --name $RESOURCE_GROUP --yes"
    fi
}

# ── Interactive menu loop ────────────────────────────────────────────────────
interactive_menu() {
    local validate_fn="$1"
    local hint_fn="$2"
    local solution_fn="$3"
    local attempt=0

    while true; do
        echo ""
        separator
        echo -e "${BOLD}  Lab Menu${NC}"
        separator
        echo -e "    ${GREEN}[V]${NC}  Validate my fix"
        echo -e "    ${YELLOW}[H]${NC}  Request a hint"
        echo -e "    ${CYAN}[S]${NC}  Show solution"
        echo -e "    ${RED}[Q]${NC}  Quit & Cleanup"
        echo ""
        echo -ne "${BOLD}  Choose an option: ${NC}"
        read -r choice
        log_to_file "Menu choice: '$choice' (attempt=$attempt)"

        case "${choice,,}" in
            v|validate)
                attempt=$((attempt+1))
                info "Validation attempt #$attempt"
                if $validate_fn; then
                    echo ""
                    header "Lab Completed Successfully!"
                    local end elapsed mins secs
                    end=$(date +%s)
                    elapsed=$((end - LAB_START_TIME))
                    mins=$((elapsed / 60))
                    secs=$((elapsed % 60))
                    ok "Time: ${mins}m ${secs}s  |  Attempts: $attempt"
                    log_to_file "LAB COMPLETED: ${mins}m ${secs}s, $attempt attempts"
                    cleanup_resources
                    return 0
                fi
                ;;
            h|hint)
                $hint_fn "$attempt"
                ;;
            s|solution)
                echo ""
                echo -ne "${YELLOW}  Show the full solution? (y/n): ${NC}"
                read -r confirm
                if [[ "${confirm,,}" =~ ^y ]]; then
                    $solution_fn
                    log_to_file "User viewed solution at attempt $attempt"
                fi
                ;;
            q|quit)
                cleanup_resources
                return 1
                ;;
            *)
                warn "Invalid choice. Use V, H, S or Q."
                ;;
        esac
    done
}

# ── Main lab runner ──────────────────────────────────────────────────────────
# Usage:  run_lab <name> <title> <description> <deploy_fn> <validate_fn> <hint_fn> <solution_fn>
run_lab() {
    local lab_name="$1" lab_title="$2" lab_desc="$3"
    local deploy_fn="$4" validate_fn="$5" hint_fn="$6" solution_fn="$7"

    LAB_START_TIME=$(date +%s)
    init_logging "$lab_name"

    header "$lab_title"
    echo -e "$lab_desc"
    echo ""

    check_prerequisites
    $deploy_fn
    interactive_menu "$validate_fn" "$hint_fn" "$solution_fn"
}
