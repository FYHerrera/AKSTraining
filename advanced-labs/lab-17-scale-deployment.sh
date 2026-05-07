#!/usr/bin/env bash
# Lab 17 – Scale a Deployment.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab17"; NS="cka-lab17"
LAB_TITLE="Lab 17 – Scale a Deployment"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Deployment ${CYAN}web${NC} (nginx) currently has 1 replica in '${NS}'.
  Scale it to ${CYAN}5${NC} replicas using kubectl scale.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" create deploy web --image=nginx:1.25 >/dev/null
    kubectl -n "$NS" rollout status deploy/web --timeout=120s >/dev/null
    ok "Deployment 'web' deployed with 1 replica."
}

validate() {
    local r; r=$(kubectl -n "$NS" get deploy web -o jsonpath='{.spec.replicas}')
    [[ "$r" == "5" ]] || { err ".spec.replicas=$r (expected 5)"; return 1; }
    local ready; ready=$(kubectl -n "$NS" get deploy web -o jsonpath='{.status.readyReplicas}')
    [[ "$ready" == "5" ]] || { err "Only $ready/5 replicas ready"; return 1; }
    ok "Scaled to 5 ready replicas."; return 0
}
hint() { info "kubectl -n $NS scale deploy web --replicas=5"; }
solution() { echo -e "\n  ${CYAN}kubectl -n $NS scale deploy web --replicas=5${NC}\n"; }

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
