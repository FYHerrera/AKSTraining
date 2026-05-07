#!/usr/bin/env bash
###############################################################################
# advanced-labs/lib/common.sh
#
# Lightweight framework for CKA-style practice labs.
# Unlike ../bash/lib/common.sh, these labs DO NOT provision AKS clusters –
# they run against the CURRENT kubectl context (AKS, kind, minikube, killercoda…).
#
# Usage in a lab script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"
#   ...define deploy / validate / hint / solution...
#   run_lab "<name>" "<title>" "<desc>" deploy validate hint solution
###############################################################################

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';     GREEN='\033[0;32m';   YELLOW='\033[1;33m'
BLUE='\033[0;34m';    CYAN='\033[0;36m';    BOLD='\033[1m';   NC='\033[0m'

# ── State ────────────────────────────────────────────────────────────────────
LOG_DIR=""; LOG_FILE=""; LAB_START_TIME=""; LAB_NAMESPACE=""

# ── Logging ──────────────────────────────────────────────────────────────────
log_to_file() { [[ -n "${LOG_FILE:-}" ]] && echo "[$(date '+%F %T')] $1" >> "$LOG_FILE"; }
log()    { echo -e "${NC}[$(date '+%H:%M:%S')] $1${NC}"; log_to_file "$1"; }
ok()     { echo -e "${GREEN}  [✓] $1${NC}";              log_to_file "[OK] $1"; }
err()    { echo -e "${RED}  [✗] $1${NC}";                log_to_file "[ERROR] $1"; }
warn()   { echo -e "${YELLOW}  [!] $1${NC}";             log_to_file "[WARN] $1"; }
info()   { echo -e "${CYAN}  [i] $1${NC}";               log_to_file "[INFO] $1"; }

header() {
    echo
    echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}    $1${NC}"
    echo -e "${BOLD}${BLUE}  ═══════════════════════════════════════════════════════${NC}"
    echo
}
separator() { echo -e "${BLUE}  ───────────────────────────────────────────────────────${NC}"; }

# ── Init logging ────────────────────────────────────────────────────────────
init_logging() {
    local lab_name="$1"
    local caller_dir
    caller_dir="$(cd "$(dirname "${BASH_SOURCE[2]:-${BASH_SOURCE[1]}}")" && pwd)"
    LOG_DIR="${caller_dir}/../logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/${lab_name}-$(date '+%Y%m%d-%H%M%S').log"
    log_to_file "=== Lab session started: $lab_name ==="
}

# ── Pre-flight: kubectl + reachable cluster ─────────────────────────────────
check_prerequisites() {
    header "Pre-flight Checks"
    if ! command -v kubectl &>/dev/null; then
        err "kubectl is not installed. Install it before running this lab."
        exit 1
    fi
    ok "kubectl found ($(kubectl version --client -o json 2>/dev/null | grep -oE '\"gitVersion\":\"v[^\"]+\"' | head -1))"

    if ! kubectl cluster-info &>/dev/null; then
        err "No reachable cluster in current kubectl context."
        info "Set a context first:  kubectl config use-context <name>"
        info "Or create a quick local cluster:  kind create cluster --name cka-practice"
        exit 1
    fi
    ok "Cluster reachable: $(kubectl config current-context)"
    echo
}

# ── Namespace helper (auto-cleaned at exit) ─────────────────────────────────
ensure_namespace() {
    LAB_NAMESPACE="$1"
    kubectl get ns "$LAB_NAMESPACE" &>/dev/null \
        || kubectl create ns "$LAB_NAMESPACE" >/dev/null
    ok "Namespace ready: $LAB_NAMESPACE"
}

# ── Cleanup ─────────────────────────────────────────────────────────────────
cleanup_resources() {
    echo; separator
    [[ -z "${LAB_NAMESPACE:-}" ]] && { warn "No namespace to clean up."; return; }
    echo -ne "${YELLOW}  Delete lab namespace '${LAB_NAMESPACE}' and its objects? (y/n): ${NC}"
    read -r resp
    if [[ "${resp,,}" =~ ^y ]]; then
        kubectl delete ns "$LAB_NAMESPACE" --wait=false &>/dev/null || true
        ok "Cleanup initiated."
    else
        warn "Resources kept in namespace '$LAB_NAMESPACE'."
    fi
}

cleanup_on_interrupt() { echo; warn "Interrupted."; cleanup_resources; exit 130; }
trap cleanup_on_interrupt INT TERM

# ── Interactive menu ────────────────────────────────────────────────────────
interactive_menu() {
    local validate_fn="$1" hint_fn="$2" solution_fn="$3" attempt=0
    while true; do
        echo; separator
        echo -e "${BOLD}  Lab Menu${NC}"; separator
        echo -e "    ${GREEN}[V]${NC}  Validate my fix"
        echo -e "    ${YELLOW}[H]${NC}  Request a hint"
        echo -e "    ${CYAN}[S]${NC}  Show solution"
        echo -e "    ${RED}[Q]${NC}  Quit & Cleanup"
        echo
        echo -ne "${BOLD}  Choose an option: ${NC}"
        read -r choice
        log_to_file "Menu choice: '$choice' (attempt=$attempt)"
        case "${choice,,}" in
            v|validate)
                attempt=$((attempt+1)); info "Validation attempt #$attempt"
                if $validate_fn; then
                    echo; header "Lab Completed Successfully!"
                    local end=$(date +%s); local elapsed=$((end - LAB_START_TIME))
                    ok "Time: $((elapsed/60))m $((elapsed%60))s | Attempts: $attempt"
                    log_to_file "LAB COMPLETED"
                    cleanup_resources; return 0
                fi
                ;;
            h|hint)     $hint_fn "$attempt" ;;
            s|solution)
                echo -ne "${YELLOW}  Show full solution? (y/n): ${NC}"; read -r c
                [[ "${c,,}" =~ ^y ]] && { $solution_fn; log_to_file "Solution viewed"; }
                ;;
            q|quit)     cleanup_resources; return 1 ;;
            *)          warn "Invalid choice. Use V, H, S or Q." ;;
        esac
    done
}

# ── Main runner ─────────────────────────────────────────────────────────────
run_lab() {
    local lab_name="$1" lab_title="$2" lab_desc="$3"
    local deploy_fn="$4" validate_fn="$5" hint_fn="$6" solution_fn="$7"
    LAB_START_TIME=$(date +%s)
    init_logging "$lab_name"
    header "$lab_title"
    echo -e "$lab_desc"; echo
    check_prerequisites
    $deploy_fn
    interactive_menu "$validate_fn" "$hint_fn" "$solution_fn"
}
