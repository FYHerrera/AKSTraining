#!/usr/bin/env bash
# Lab 22 – Pod with SecurityContext (UID 1000) + node affinity.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab22"; NS="cka-lab22"
LAB_TITLE="Lab 22 – SecurityContext + node affinity"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Create Pod ${CYAN}secure-pod${NC} in '${NS}' from image ${CYAN}nginx${NC} that:
    - Runs as non-root user UID 1000
    - Has node affinity REQUIRING a node with label ${CYAN}tier=secure${NC}
  This lab labels one node with tier=secure for you.
"

deploy() {
    ensure_namespace "$NS"
    local node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    kubectl label node "$node" tier=secure --overwrite >/dev/null
    ok "Node '$node' labelled tier=secure. Now create secure-pod."
}

validate() {
    local p="$(kubectl -n "$NS" get pod secure-pod -o json 2>/dev/null)"
    [[ -z "$p" ]] && { err "Pod missing"; return 1; }
    local uid="$(echo "$p" | jq -r '.spec.securityContext.runAsUser // .spec.containers[0].securityContext.runAsUser')"
    [[ "$uid" == "1000" ]] || { err "runAsUser must be 1000, got '$uid'"; return 1; }
    local nonroot="$(echo "$p" | jq -r '.spec.securityContext.runAsNonRoot // .spec.containers[0].securityContext.runAsNonRoot')"
    [[ "$nonroot" == "true" ]] || warn "Consider also runAsNonRoot: true"
    echo "$p" | jq -e '.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[]
        | select(.key=="tier" and .values[0]=="secure")' &>/dev/null \
        || { err "Required node affinity on tier=secure missing"; return 1; }
    [[ "$(echo "$p" | jq -r '.status.phase')" == "Running" ]] || { err "Pod not Running"; return 1; }
    ok "secure-pod running with UID 1000 and required affinity."; return 0
}
hint() {
    local a="${1:-0}"
    if [[ $a -lt 2 ]]; then info "Use spec.securityContext.runAsUser: 1000 (note: nginx default image won't bind to port 80 as non-root; use unprivileged image or expect a CrashLoop — for the exam, use 'nginxinc/nginx-unprivileged' or 'busybox sleep')."
    else                    info "Use requiredDuringSchedulingIgnoredDuringExecution with key=tier, values=[secure]."
    fi
}
solution() {
cat <<EOF

  kubectl -n ${NS} apply -f - <<'YAML'
  apiVersion: v1
  kind: Pod
  metadata: { name: secure-pod }
  spec:
    securityContext: { runAsUser: 1000, runAsNonRoot: true }
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - { key: tier, operator: In, values: [secure] }
    containers:
    - name: web
      image: nginxinc/nginx-unprivileged:1.25   # bind to 8080 as non-root
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
