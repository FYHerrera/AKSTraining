#!/usr/bin/env bash
# Lab 03 – Create the missing IngressClass first, then an Ingress.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab03"; NS="cka-lab03"
LAB_TITLE="Lab 03 – Ingress + IngressClass"
LAB_DESC="
  ${BOLD}Scenario${NC}
  An app exposes Service ${CYAN}web-svc${NC} on port 80 in '${NS}'.
  The cluster has the nginx controller installed, but the IngressClass
  ${CYAN}nginx${NC} is MISSING. Create:
    1) IngressClass ${CYAN}nginx${NC} (controller: k8s.io/ingress-nginx, set as default)
    2) Ingress ${CYAN}web-ingress${NC} routing ${CYAN}example.com/${NC} to web-svc:80

  ${BOLD}Docs${NC} https://kubernetes.io/docs/concepts/services-networking/ingress/
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - { name: web, image: nginx:1.25, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: web-svc }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
YAML
    ok "Deployment + Service deployed. IngressClass is intentionally missing."
}

validate() {
    local ic="$(kubectl get ingressclass nginx -o json 2>/dev/null)"
    [[ -z "$ic" ]] && { err "IngressClass 'nginx' missing"; return 1; }
    [[ "$(echo "$ic" | jq -r '.metadata.annotations."ingressclass.kubernetes.io/is-default-class"')" == "true" ]] \
        || { err "IngressClass should be marked default"; return 1; }
    local ing="$(kubectl -n "$NS" get ingress web-ingress -o json 2>/dev/null)"
    [[ -z "$ing" ]] && { err "Ingress 'web-ingress' missing"; return 1; }
    [[ "$(echo "$ing" | jq -r '.spec.ingressClassName // .spec.rules[0].host')" == "nginx" \
       || "$(echo "$ing" | jq -r '.spec.ingressClassName')" == "nginx" ]] || { err "Ingress not using class 'nginx'"; return 1; }
    [[ "$(echo "$ing" | jq -r '.spec.rules[0].http.paths[0].backend.service.name')" == "web-svc" ]] \
        || { err "Backend service name must be 'web-svc'"; return 1; }
    ok "IngressClass + Ingress configured correctly."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "kubectl get ingressclass — none. Create one of kind: IngressClass."
    elif [[ $a -lt 4 ]]; then info "Annotation 'ingressclass.kubernetes.io/is-default-class: \"true\"' makes it default."
    else                       info "On the Ingress resource set spec.ingressClassName: nginx."
    fi
}

solution() {
cat <<EOF

  kubectl apply -f - <<'YAML'
  apiVersion: networking.k8s.io/v1
  kind: IngressClass
  metadata:
    name: nginx
    annotations:
      ingressclass.kubernetes.io/is-default-class: "true"
  spec:
    controller: k8s.io/ingress-nginx
  ---
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata: { name: web-ingress, namespace: ${NS} }
  spec:
    ingressClassName: nginx
    rules:
    - host: example.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service: { name: web-svc, port: { number: 80 } }
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
