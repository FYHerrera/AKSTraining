#!/usr/bin/env bash
###############################################################################
# Lab 05 – Network Policy Blocking Traffic
#
# Scenario : A NetworkPolicy allows ingress to the backend only from pods
#            with the wrong label selector, blocking the frontend.
# Objective: Fix the NetworkPolicy so the frontend can reach the backend.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="network-policy"
LAB_TITLE="Lab 05 – Network Policy Blocking Traffic"
LAB_DESC="
  ${BOLD}Scenario${NC}
  A microservices app has a ${CYAN}frontend${NC} and a ${CYAN}backend${NC} service.
  A NetworkPolicy was applied to restrict access to the backend,
  but now the frontend ${RED}cannot reach${NC} the backend service.

  ${BOLD}Objective${NC}
  Fix the issue so the frontend pod can reach the backend via
  the ${CYAN}backend-svc${NC} service on port 80.

  ${BOLD}Useful commands${NC}
    kubectl get pods,svc
    kubectl get networkpolicy
    kubectl describe networkpolicy <name>
    kubectl exec <frontend-pod> -- wget -qO- http://backend-svc --timeout=5
"

# ── Deploy ──────────────────────────────────────────────────────────────────
deploy() {
    create_aks_cluster "$LAB_NAME"

    header "Injecting Lab Scenario"

    # Backend
    log "Deploying backend service..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        tier: api
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: default
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
EOF
    ok "Backend deployment + service created"

    # Frontend
    log "Deploying frontend pod..."
    kubectl run frontend --image=busybox:1.36 --labels="app=frontend,tier=web" \
        --restart=Never -- sh -c "sleep 3600" 2>/dev/null || true
    kubectl wait --for=condition=Ready pod/frontend --timeout=120s &>/dev/null
    ok "Frontend pod created"

    # Broken NetworkPolicy — allows from "app: gateway" instead of "app: frontend"
    log "Applying NetworkPolicy..."
    kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-ingress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: gateway
    ports:
    - protocol: TCP
      port: 80
EOF
    ok "NetworkPolicy applied"

    sleep 5
    echo ""
    separator
    err "Frontend CANNOT reach the backend service!"
    info "Try:  kubectl exec frontend -- wget -qO- http://backend-svc --timeout=5"
    info "Use the menu below to validate once you've fixed the issue."
}

# ── Validate ────────────────────────────────────────────────────────────────
validate() {
    local result
    result=$(kubectl exec frontend -- wget -qO- http://backend-svc --timeout=10 2>&1) || true

    if echo "$result" | grep -qi "nginx\|Welcome"; then
        ok "Frontend can reach the backend!"
        return 0
    else
        err "Frontend still cannot reach the backend."
        err "Response: $(echo "$result" | head -2)"
        return 1
    fi
}

# ── Hints ───────────────────────────────────────────────────────────────────
hint() {
    local attempt="${1:-0}"
    echo ""
    if [[ $attempt -lt 2 ]]; then
        info "Hint 1: Look at the NetworkPolicy applied to backend pods."
        info "  kubectl describe networkpolicy backend-allow-ingress"
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2: The ingress rule allows traffic from pods with a"
        info "  specific label. What label does the frontend pod have?"
        info "  kubectl get pod frontend --show-labels"
    else
        info "Hint 3: The policy allows from 'app=gateway' but the"
        info "  frontend pod has label 'app=frontend'."
        info "  Fix the podSelector in the ingress rule."
    fi
}

# ── Solution ────────────────────────────────────────────────────────────────
solution() {
    echo ""
    header "Solution"
    info "Fix the NetworkPolicy to allow traffic from the frontend:"
    cat <<'SOL'

  kubectl apply -f - <<EOF
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: backend-allow-ingress
    namespace: default
  spec:
    podSelector:
      matchLabels:
        app: backend
    policyTypes:
    - Ingress
    ingress:
    - from:
      - podSelector:
          matchLabels:
            app: frontend
      ports:
      - protocol: TCP
        port: 80
  EOF

SOL
    info "Explanation: The NetworkPolicy allowed ingress only from pods"
    info "with label 'app: gateway', but the frontend uses 'app: frontend'."
    info "Changing the podSelector to match 'app: frontend' fixes it."
}

# ── Run ─────────────────────────────────────────────────────────────────────
run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
