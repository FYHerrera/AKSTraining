#!/usr/bin/env bash
# Lab 15 – nodeSelector to schedule on disk=ssd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab15"; NS="cka-lab15"
LAB_TITLE="Lab 15 – nodeSelector scheduling"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Schedule Pod ${CYAN}nginx${NC} (image nginx) on a node labelled ${CYAN}disk=ssd${NC}.
  This lab labels one of your nodes with disk=ssd.

  ${BOLD}Docs${NC} https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/
"

deploy() {
    ensure_namespace "$NS"
    local node="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
    [[ -z "$node" ]] && { err "No nodes available"; exit 1; }
    kubectl label node "$node" disk=ssd --overwrite >/dev/null
    ok "Labelled node '$node' with disk=ssd. Now create the Pod with a matching nodeSelector."
}

validate() {
    local p="$(kubectl -n "$NS" get pod nginx -o json 2>/dev/null)"
    [[ -z "$p" ]] && { err "Pod nginx missing"; return 1; }
    [[ "$(echo "$p" | jq -r '.spec.nodeSelector.disk')" == "ssd" ]] || { err "spec.nodeSelector.disk must be 'ssd'"; return 1; }
    [[ "$(echo "$p" | jq -r '.status.phase')" == "Running" ]] || { err "Pod not Running (scheduling failed?)"; return 1; }
    local pn="$(echo "$p" | jq -r '.spec.nodeName')"
    [[ "$(kubectl get node "$pn" -o jsonpath='{.metadata.labels.disk}')" == "ssd" ]] || { err "Pod scheduled on node without disk=ssd"; return 1; }
    ok "Pod scheduled on labelled node '$pn'."; return 0
}
hint() { info "Add  spec.nodeSelector:\n    disk: ssd  to the Pod manifest."; }
solution() {
cat <<EOF

  kubectl -n ${NS} apply -f - <<'YAML'
  apiVersion: v1
  kind: Pod
  metadata: { name: nginx }
  spec:
    nodeSelector: { disk: ssd }
    containers:
    - { name: nginx, image: nginx }
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
