#!/usr/bin/env bash
# Lab 21 – Rolling update + rollback.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab21"; NS="cka-lab21"
LAB_TITLE="Lab 21 – Rolling update + rollback"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Deployment ${CYAN}app-deployment${NC} runs nginx:1.24 with 3 replicas.
  Steps:
    1. Update its image to a deliberately broken tag ${CYAN}nginx:doesnotexist${NC}
       and observe that the rollout fails (ImagePullBackOff).
    2. Rollback to the previous (working) revision.
  After rollback, all 3 pods must be Running with image nginx:1.24.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" create deploy app-deployment --image=nginx:1.24 --replicas=3 >/dev/null
    kubectl -n "$NS" rollout status deploy/app-deployment --timeout=120s >/dev/null
    ok "app-deployment running at nginx:1.24."
}

validate() {
    local img; img=$(kubectl -n "$NS" get deploy app-deployment -o jsonpath='{.spec.template.spec.containers[0].image}')
    [[ "$img" == "nginx:1.24" ]] || { err "Image is '$img' (expected nginx:1.24 after rollback)"; return 1; }
    local ready; ready=$(kubectl -n "$NS" get deploy app-deployment -o jsonpath='{.status.readyReplicas}')
    [[ "$ready" == "3" ]] || { err "Only $ready/3 replicas ready"; return 1; }
    local rev_count; rev_count=$(kubectl -n "$NS" rollout history deploy/app-deployment | grep -cE '^[0-9]+')
    [[ "$rev_count" -ge 2 ]] || { err "Need at least 2 revisions in history (update + rollback)"; return 1; }
    ok "Rollback restored nginx:1.24 with all 3 replicas Ready."; return 0
}
hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Update:  kubectl set image deploy/app-deployment nginx=nginx:doesnotexist"
    else                       info "Rollback:  kubectl rollout undo deploy/app-deployment"
    fi
}
solution() {
cat <<EOF

  kubectl -n ${NS} set image deploy/app-deployment nginx=nginx:doesnotexist
  kubectl -n ${NS} rollout status deploy/app-deployment --timeout=60s   # will fail
  kubectl -n ${NS} rollout undo  deploy/app-deployment
  kubectl -n ${NS} rollout status deploy/app-deployment

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
