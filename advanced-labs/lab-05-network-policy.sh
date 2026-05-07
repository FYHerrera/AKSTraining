#!/usr/bin/env bash
# Lab 05 – NetworkPolicy: allow ingress from a specific namespace ONLY on port 8080.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab05"; NS="cka-lab05"; SRC_NS="${NS}-clients"
LAB_TITLE="Lab 05 – NetworkPolicy by namespace + port"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Namespace ${CYAN}${NS}${NC} runs a service on port 8080.
  Only pods from namespace ${CYAN}${SRC_NS}${NC} (label kubernetes.io/metadata.name=${SRC_NS})
  may connect, and only to TCP port 8080. All other ingress must be denied.

  Create a NetworkPolicy named ${CYAN}allow-clients-8080${NC} in ${NS}.

  ${BOLD}Docs${NC} https://kubernetes.io/docs/concepts/services-networking/network-policies/
"

deploy() {
    ensure_namespace "$NS"
    kubectl get ns "$SRC_NS" &>/dev/null || kubectl create ns "$SRC_NS" >/dev/null
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: api }
spec:
  replicas: 1
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
      - name: api
        image: hashicorp/http-echo:1.0
        args: ["-listen=:8080","-text=ok"]
        ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: api-svc }
spec:
  selector: { app: api }
  ports: [{ port: 8080, targetPort: 8080 }]
YAML
    ok "Target deployment 'api' in $NS, client namespace '$SRC_NS' ready. Now create the NetworkPolicy."
    info "Cleanup hint: namespace '$SRC_NS' will NOT be auto-deleted; remove with 'kubectl delete ns $SRC_NS'."
}

validate() {
    local np="$(kubectl -n "$NS" get netpol allow-clients-8080 -o json 2>/dev/null)"
    [[ -z "$np" ]] && { err "NetworkPolicy 'allow-clients-8080' missing"; return 1; }
    echo "$np" | jq -e '.spec.policyTypes | index("Ingress")' &>/dev/null || { err "policyTypes must include Ingress"; return 1; }
    echo "$np" | jq -e ".spec.ingress[0].from[] | select(.namespaceSelector.matchLabels.\"kubernetes.io/metadata.name\"==\"$SRC_NS\")" &>/dev/null \
        || { err "Ingress.from must select namespace '$SRC_NS' by label kubernetes.io/metadata.name"; return 1; }
    echo "$np" | jq -e '.spec.ingress[0].ports[] | select(.port==8080 and (.protocol==null or .protocol=="TCP"))' &>/dev/null \
        || { err "Must allow only port 8080/TCP"; return 1; }
    ok "NetworkPolicy looks correct."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "podSelector: {} applies the policy to ALL pods in ${NS}."
    elif [[ $a -lt 4 ]]; then info "Use namespaceSelector with label kubernetes.io/metadata.name=${SRC_NS}."
    else                       info "Add a 'ports' clause inside the same 'from' rule to scope to 8080."
    fi
}

solution() {
cat <<EOF

  kubectl apply -f - <<'YAML'
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata: { name: allow-clients-8080, namespace: ${NS} }
  spec:
    podSelector: {}
    policyTypes: [Ingress]
    ingress:
    - from:
      - namespaceSelector:
          matchLabels: { kubernetes.io/metadata.name: ${SRC_NS} }
      ports:
      - { protocol: TCP, port: 8080 }
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
