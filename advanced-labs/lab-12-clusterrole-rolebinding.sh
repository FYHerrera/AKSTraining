#!/usr/bin/env bash
# Lab 12 – ClusterRole + namespaced RoleBinding to a ServiceAccount.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab12"; NS="cka-lab12"
LAB_TITLE="Lab 12 – ClusterRole + namespaced RoleBinding"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Create:
    1) ServiceAccount ${CYAN}deploy-sa${NC} in '${NS}'.
    2) ClusterRole ${CYAN}deploy-manager${NC} that allows get,list,create,update,delete
       on resource 'deployments' (apiGroup apps).
    3) RoleBinding ${CYAN}deploy-sa-bind${NC} in '${NS}' that binds 'deploy-manager'
       to deploy-sa (NOT a ClusterRoleBinding — must be namespace scoped).

  Validate:  kubectl auth can-i create deployments --as=system:serviceaccount:${NS}:deploy-sa -n ${NS}

  ${BOLD}Docs${NC} https://kubernetes.io/docs/reference/access-authn-authz/authorization/
"

deploy() { ensure_namespace "$NS"; ok "Create the SA, ClusterRole and RoleBinding."; }

validate() {
    kubectl -n "$NS" get sa deploy-sa &>/dev/null || { err "ServiceAccount missing"; return 1; }
    kubectl get clusterrole deploy-manager &>/dev/null || { err "ClusterRole missing"; return 1; }
    local rb="$(kubectl -n "$NS" get rolebinding deploy-sa-bind -o json 2>/dev/null)"
    [[ -z "$rb" ]] && { err "RoleBinding missing in namespace $NS"; return 1; }
    [[ "$(echo "$rb" | jq -r '.roleRef.kind')" == "ClusterRole" ]] || { err "roleRef.kind must be ClusterRole"; return 1; }
    [[ "$(echo "$rb" | jq -r '.roleRef.name')" == "deploy-manager" ]] || { err "roleRef.name must be deploy-manager"; return 1; }
    local can="$(kubectl auth can-i create deployments --as="system:serviceaccount:${NS}:deploy-sa" -n "$NS" 2>/dev/null)"
    [[ "$can" == "yes" ]] || { err "auth can-i: $can (expected yes)"; return 1; }
    local cant="$(kubectl auth can-i create deployments --as="system:serviceaccount:${NS}:deploy-sa" -n default 2>/dev/null)"
    [[ "$cant" == "no" ]] || warn "Permission also granted in default namespace ($cant)"
    ok "RBAC configured correctly."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "kubectl create clusterrole -h  /  kubectl create rolebinding -h"
    else                       info "Bind ClusterRole to SA via 'kubectl create rolebinding ... --clusterrole=...' in -n $NS"
    fi
}

solution() {
cat <<EOF

  kubectl -n ${NS} create sa deploy-sa
  kubectl create clusterrole deploy-manager \\
      --verb=get,list,create,update,delete --resource=deployments
  kubectl -n ${NS} create rolebinding deploy-sa-bind \\
      --clusterrole=deploy-manager --serviceaccount=${NS}:deploy-sa

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
