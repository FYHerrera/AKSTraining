#!/usr/bin/env bash
# Lab 07 – Expose a named container port via a NodePort Service.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab07"; NS="cka-lab07"
LAB_TITLE="Lab 07 – Expose container port by name (NodePort)"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Pod ${CYAN}nginx${NC} exposes a named container port 'http-websvc' (80).
  Create a NodePort Service ${CYAN}front-end-svc${NC} that targets that
  named port on port 80.

  ${BOLD}Docs${NC} https://kubernetes.io/docs/concepts/services-networking/service/
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata: { name: nginx, labels: { app: nginx } }
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    ports:
    - { name: http-websvc, containerPort: 80 }
YAML
    kubectl -n "$NS" wait --for=condition=Ready pod/nginx --timeout=120s &>/dev/null
    ok "Pod 'nginx' running. Now create the NodePort service."
}

validate() {
    local s="$(kubectl -n "$NS" get svc front-end-svc -o json 2>/dev/null)"
    [[ -z "$s" ]] && { err "Service 'front-end-svc' missing"; return 1; }
    [[ "$(echo "$s" | jq -r '.spec.type')" == "NodePort" ]] || { err "Service must be NodePort"; return 1; }
    [[ "$(echo "$s" | jq -r '.spec.ports[0].targetPort')" == "http-websvc" ]] \
        || { err "targetPort must be the named port 'http-websvc'"; return 1; }
    [[ "$(echo "$s" | jq -r '.spec.ports[0].port')" == "80" ]] || { err "port must be 80"; return 1; }
    ok "Service is correct."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "kubectl expose pod nginx ... --target-port http-websvc"
    else                       info "kubectl -n $NS expose pod nginx --name front-end-svc --port 80 --target-port http-websvc --type NodePort"
    fi
}

solution() { echo -e "\n  ${CYAN}kubectl -n $NS expose pod nginx --name front-end-svc --port 80 --target-port http-websvc --type NodePort${NC}\n"; }

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
