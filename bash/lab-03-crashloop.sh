#!/usr/bin/env bash
###############################################################################
# Lab 03 – CrashLoopBackOff
#
# Scenario : A Deployment has a liveness probe pointing at the wrong port,
#            causing Kubernetes to kill and restart the container repeatedly.
# Objective: Fix the deployment so all pods are Running and Ready.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="crashloop"
LAB_TITLE="Lab 03 – CrashLoopBackOff"
LAB_DESC="
  ${BOLD}Scenario${NC}
  The ${CYAN}web-app${NC} deployment was working fine until someone changed
  the health-check configuration. Now all pods are in
  ${RED}CrashLoopBackOff${NC} state.

  ${BOLD}Objective${NC}
  Fix the deployment so all 2 replicas are ${GREEN}Running${NC} and ${GREEN}Ready (1/1)${NC}.

  ${BOLD}Useful commands${NC}
    kubectl get pods
    kubectl describe pod <name>
    kubectl logs <pod-name>
    kubectl get deployment web-app -o yaml
"

# ── Deploy ──────────────────────────────────────────────────────────────────
deploy() {
    create_aks_cluster "$LAB_NAME"

    header "Injecting Lab Scenario"

    log "Creating deployment with bad liveness probe..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
          failureThreshold: 2
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
EOF
    ok "Deployment 'web-app' created"

    log "Waiting for containers to start crashing..."
    sleep 25

    echo ""
    separator
    err "Pods are entering CrashLoopBackOff!"
    kubectl get pods -l app=web-app --no-headers 2>/dev/null
    echo ""
    info "Investigate why the pods keep restarting."
    info "Use the menu below to validate once you've fixed the issue."
}

# ── Validate ────────────────────────────────────────────────────────────────
validate() {
    local ready
    ready=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null \
        | grep "Running" | grep -c "1/1" || echo 0)

    if [[ "$ready" -ge 2 ]]; then
        ok "Both replicas are Running and Ready!"
        return 0
    else
        err "Not all replicas are healthy yet."
        kubectl get pods -l app=web-app --no-headers 2>/dev/null | head -5
        return 1
    fi
}

# ── Hints ───────────────────────────────────────────────────────────────────
hint() {
    local attempt="${1:-0}"
    echo ""
    if [[ $attempt -lt 2 ]]; then
        info "Hint 1: Describe a pod and look at the Events section."
        info "  Pay attention to Liveness probe failures."
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2: nginx listens on port 80 by default."
        info "  What port is the liveness probe configured to check?"
    else
        info "Hint 3: The liveness probe targets port 8080 and path /healthz."
        info "  nginx listens on port 80 and serves content at /."
        info "  Fix both the port and the path."
    fi
}

# ── Solution ────────────────────────────────────────────────────────────────
solution() {
    echo ""
    header "Solution"
    info "Fix the liveness probe to use the correct port and path:"
    echo ""
    cat <<'SOL'
  kubectl patch deployment web-app --type=json -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 80},
    {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/path", "value": "/"}
  ]'
SOL
    echo ""
    info "Or edit the deployment directly:"
    echo -e "  ${CYAN}kubectl edit deployment web-app${NC}"
    info "  Change livenessProbe.httpGet.port from 8080 to 80"
    info "  Change livenessProbe.httpGet.path from /healthz to /"
    echo ""
    info "Explanation: nginx listens on port 80 and serves the default page"
    info "at /. The probe was hitting port 8080 (nothing there) and path"
    info "/healthz (does not exist). After 2 consecutive failures (6s)"
    info "kubelet restarts the container, causing CrashLoopBackOff."
}

# ── Run ─────────────────────────────────────────────────────────────────────
run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
