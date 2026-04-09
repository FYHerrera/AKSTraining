#!/usr/bin/env bash
###############################################################################
# Lab 02 – Pod Stuck in Pending
#
# Scenario : A Deployment uses a nodeSelector label that does not exist on
#            any node, causing all replicas to remain Pending.
# Objective: Make all 3 replicas of the deployment reach Running state.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="pod-pending"
LAB_TITLE="Lab 02 – Pod Stuck in Pending"
LAB_DESC="
  ${BOLD}Scenario${NC}
  A developer created a Deployment called ${CYAN}web-app${NC} with 3 replicas,
  but all pods are stuck in ${RED}Pending${NC} state. The cluster has available
  resources, but something prevents scheduling.

  ${BOLD}Objective${NC}
  Make all 3 pods of the ${CYAN}web-app${NC} deployment reach ${GREEN}Running${NC} state.

  ${BOLD}Useful commands${NC}
    kubectl get pods
    kubectl describe pod <name>
    kubectl get nodes --show-labels
"

# ── Deploy ──────────────────────────────────────────────────────────────────
deploy() {
    create_aks_cluster "$LAB_NAME"

    header "Injecting Lab Scenario"

    log "Creating deployment with scheduling issue..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      nodeSelector:
        disktype: ssd
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
EOF
    ok "Deployment 'web-app' created"

    # Wait a moment for the pods to appear
    sleep 5
    local pending
    pending=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep -c "Pending" || echo 0)

    echo ""
    separator
    err "All $pending pods are stuck in Pending state!"
    info "Investigate why the pods cannot be scheduled."
    info "Use the menu below to validate once you've fixed the issue."
}

# ── Validate ────────────────────────────────────────────────────────────────
validate() {
    local running
    running=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null | grep -c "Running" || echo 0)

    if [[ "$running" -ge 3 ]]; then
        ok "All 3 replicas are Running!"
        return 0
    else
        err "Only $running/3 replicas are Running."
        kubectl get pods -l app=web-app --no-headers 2>/dev/null | head -5
        return 1
    fi
}

# ── Hints ───────────────────────────────────────────────────────────────────
hint() {
    local attempt="${1:-0}"
    echo ""
    if [[ $attempt -lt 2 ]]; then
        info "Hint 1: Describe a pending pod and read the Events section."
        info "  kubectl describe pod <pod-name>"
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2: The pod requires a specific node label to be scheduled."
        info "  Check: kubectl get nodes --show-labels"
        info "  Compare with the deployment's nodeSelector."
    else
        info "Hint 3: The nodeSelector asks for 'disktype=ssd' but no node"
        info "  has that label. Either label a node or remove the selector."
    fi
}

# ── Solution ────────────────────────────────────────────────────────────────
solution() {
    echo ""
    header "Solution"
    info "Option A – Label the nodes so they match the selector:"
    echo -e "  ${CYAN}kubectl label nodes --all disktype=ssd${NC}"
    echo ""
    info "Option B – Remove the nodeSelector from the deployment:"
    echo -e "  ${CYAN}kubectl patch deployment web-app --type=json \\
    -p='[{\"op\": \"remove\", \"path\": \"/spec/template/spec/nodeSelector\"}]'${NC}"
    echo ""
    info "Explanation: The deployment's spec.template.spec.nodeSelector"
    info "requires 'disktype: ssd', but none of the cluster nodes have"
    info "that label, so the scheduler cannot place the pods."
}

# ── Run ─────────────────────────────────────────────────────────────────────
run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
