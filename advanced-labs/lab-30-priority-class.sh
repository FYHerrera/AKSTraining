#!/usr/bin/env bash
# Lab 30 – PriorityClass + patch a Deployment to use it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab30"; NS="priority"
LAB_TITLE="Lab 30 – PriorityClass"
LAB_DESC="
  ${BOLD}Scenario${NC}
  In namespace ${CYAN}priority${NC} runs Deployment ${CYAN}busybox-logger${NC}.
    1) Create PriorityClass ${CYAN}high-priority${NC} with value
       ${CYAN}999999999${NC} (one less than the user-defined max 1,000,000,000).
    2) Patch the Deployment to use that priorityClassName.
    3) Make sure the Deployment rolls out successfully.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: busybox-logger }
spec:
  replicas: 1
  selector: { matchLabels: { app: blog } }
  template:
    metadata: { labels: { app: blog } }
    spec:
      containers:
      - { name: log, image: busybox:1.36, command: ["sh","-c","while true; do echo log; sleep 5; done"] }
YAML
    kubectl -n "$NS" rollout status deploy/busybox-logger --timeout=120s >/dev/null
    ok "Deployment busybox-logger running. Create the PriorityClass and patch."
}

validate() {
    local pc="$(kubectl get priorityclass high-priority -o json 2>/dev/null)"
    [[ -z "$pc" ]] && { err "PriorityClass high-priority missing"; return 1; }
    [[ "$(echo "$pc" | jq -r '.value')" == "999999999" ]] || { err "PriorityClass value must be 999999999"; return 1; }
    local pcn; pcn=$(kubectl -n "$NS" get deploy busybox-logger -o jsonpath='{.spec.template.spec.priorityClassName}')
    [[ "$pcn" == "high-priority" ]] || { err "Deployment not using priorityClassName=high-priority (got '$pcn')"; return 1; }
    kubectl -n "$NS" rollout status deploy/busybox-logger --timeout=60s >/dev/null || { err "Deployment did not roll out"; return 1; }
    ok "PriorityClass + Deployment patched correctly."; return 0
}
hint() {
    local a="${1:-0}"
    if [[ $a -lt 2 ]]; then info "kubectl create priorityclass high-priority --value=999999999 --description='HP'"
    else                    info "kubectl -n $NS patch deploy busybox-logger --type=merge -p '{\"spec\":{\"template\":{\"spec\":{\"priorityClassName\":\"high-priority\"}}}}'"
    fi
}
solution() {
cat <<EOF

  kubectl create priorityclass high-priority --value=999999999 --description="High"
  kubectl -n ${NS} patch deploy busybox-logger --type=merge \\
    -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
  kubectl -n ${NS} rollout status deploy/busybox-logger

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
