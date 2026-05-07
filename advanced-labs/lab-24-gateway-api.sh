#!/usr/bin/env bash
# Lab 24 – Migrate Ingress to Gateway API (Gateway + HTTPRoute).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab24"; NS="cka-lab24"
LAB_TITLE="Lab 24 – Migrate Ingress to Gateway API"
LAB_DESC="
  ${BOLD}Scenario${NC}
  An Ingress resource ${CYAN}web${NC} routes ${CYAN}gateway.web.k8s.local${NC}/
  to Service ${CYAN}web-svc${NC}:80. Migrate to Gateway API:
    - Use existing GatewayClass ${CYAN}nginx${NC} (create if missing)
    - Create Gateway ${CYAN}web-gateway${NC} listening on host gateway.web.k8s.local
    - Create HTTPRoute ${CYAN}web-route${NC} matching the same host & rules
    - DELETE the existing Ingress 'web'

  ${BOLD}Docs${NC} https://gateway-api.sigs.k8s.io/guides/http-routing/

  ${BOLD}Prereq${NC}: Gateway API CRDs must be installed in the cluster.
"

deploy() {
    ensure_namespace "$NS"
    if ! kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        warn "Gateway API CRDs not installed. Installing standard channel v1.0.0..."
        kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml >/dev/null
    fi
    kubectl get gatewayclass nginx &>/dev/null || kubectl apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata: { name: nginx }
spec: { controllerName: gateway.nginx.org/nginx-gateway-controller }
YAML
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec: { containers: [{ name: web, image: nginx:1.25, ports: [{ containerPort: 80 }] }] }
---
apiVersion: v1
kind: Service
metadata: { name: web-svc }
spec: { selector: { app: web }, ports: [{ port: 80, targetPort: 80 }] }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web }
spec:
  rules:
  - host: gateway.web.k8s.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: web-svc, port: { number: 80 } } }
YAML
    ok "Existing Ingress 'web' is in '$NS'. Replace it with Gateway + HTTPRoute and delete it."
}

validate() {
    kubectl -n "$NS" get gateway web-gateway -o json 2>/dev/null \
        | jq -e '.spec.gatewayClassName=="nginx" and (.spec.listeners[].hostname=="gateway.web.k8s.local")' &>/dev/null \
        || { err "Gateway 'web-gateway' missing or wrong (class=nginx, hostname=gateway.web.k8s.local)"; return 1; }
    kubectl -n "$NS" get httproute web-route -o json 2>/dev/null \
        | jq -e '.spec.hostnames | index("gateway.web.k8s.local")' &>/dev/null \
        || { err "HTTPRoute 'web-route' missing or wrong hostname"; return 1; }
    kubectl -n "$NS" get httproute web-route -o json \
        | jq -e '.spec.rules[].backendRefs[] | select(.name=="web-svc" and .port==80)' &>/dev/null \
        || { err "HTTPRoute backendRef must be web-svc:80"; return 1; }
    kubectl -n "$NS" get ingress web &>/dev/null && { err "Old Ingress 'web' still present — delete it"; return 1; }
    ok "Migration complete."; return 0
}
hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Create the Gateway with one listener on port 80, hostname gateway.web.k8s.local."
    elif [[ $a -lt 4 ]]; then info "HTTPRoute spec.parentRefs[] points to the Gateway."
    else                       info "After verifying:  kubectl -n $NS delete ingress web"
    fi
}
solution() {
cat <<EOF

  kubectl -n ${NS} apply -f - <<'YAML'
  apiVersion: gateway.networking.k8s.io/v1
  kind: Gateway
  metadata: { name: web-gateway }
  spec:
    gatewayClassName: nginx
    listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: gateway.web.k8s.local
  ---
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata: { name: web-route }
  spec:
    parentRefs: [{ name: web-gateway }]
    hostnames: [gateway.web.k8s.local]
    rules:
    - matches: [{ path: { type: PathPrefix, value: / } }]
      backendRefs: [{ name: web-svc, port: 80 }]
  YAML

  kubectl -n ${NS} delete ingress web

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
