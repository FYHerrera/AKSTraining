#!/usr/bin/env bash
###############################################################################
# Lab 06 – Node Taint / Scheduling Issue
#
# Scenario : All nodes have been tainted with NoSchedule, preventing any
#            new pods from being scheduled.
# Objective: Fix the taints so all pods reach Running state.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="node-taint"
LAB_TITLE="Lab 06 – Node Taint / Scheduling Issue"
LAB_DESC="
  ${BOLD}Scenario${NC}
  The operations team applied maintenance taints to all nodes but
  forgot to remove them. Now the ${CYAN}web-app${NC} deployment has pods
  stuck in ${RED}Pending${NC} because no node will accept them.

  ${BOLD}Objective${NC}
  Fix the scheduling issue so all 3 replicas are ${GREEN}Running${NC}.

  ${BOLD}Useful commands${NC}
    kubectl get pods
    kubectl describe pod <name>
    kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
    kubectl describe node <name>
"

# ── Deploy ──────────────────────────────────────────────────────────────────
deploy() {
    create_aks_cluster "$LAB_NAME"

    header "Injecting Lab Scenario"

    # Taint all nodes
    log "Applying maintenance taints to all nodes..."
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
        kubectl taint nodes "$node" maintenance=scheduled:NoSchedule --overwrite 2>/dev/null || true
    done
    ok "Taints applied to all nodes"

    # Deploy app (will stay Pending)
    log "Creating deployment..."
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

    sleep 8
    echo ""
    separator
    err "All pods are Pending – no node will accept them!"
    kubectl get pods -l app=web-app --no-headers 2>/dev/null
    echo ""
    info "Investigate why pods cannot be scheduled."
    info "Use the menu below to validate once you've fixed the issue."
}

# ── Validate ────────────────────────────────────────────────────────────────
validate() {
    local running
    running=$(kubectl get pods -l app=web-app --no-headers 2>/dev/null \
        | grep -c "Running" || echo 0)

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
        info "Hint 1: Describe one of the pending pods."
        info "  Look at the Events section for scheduling warnings."
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2: Check the taints on the cluster nodes."
        info "  kubectl describe node <node-name> | grep -A5 Taints"
    else
        info "Hint 3: Nodes have a 'maintenance=scheduled:NoSchedule' taint."
        info "  Either remove the taint or add a toleration to the deployment."
    fi
}

# ── Solution ────────────────────────────────────────────────────────────────
solution() {
    echo ""
    header "Solution"
    info "Option A – Remove the taint from all nodes:"
    echo -e "  ${CYAN}kubectl taint nodes --all maintenance=scheduled:NoSchedule-${NC}"
    echo ""
    info "Option B – Add a toleration to the deployment:"
    cat <<'SOL'

  kubectl patch deployment web-app --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/tolerations", "value": [
      {"key": "maintenance", "operator": "Equal", "value": "scheduled", "effect": "NoSchedule"}
    ]}
  ]'

SOL
    info "Explanation: Every node has the taint 'maintenance=scheduled:NoSchedule'."
    info "Pods without a matching toleration cannot be placed on those nodes."
    info "Removing the taint (Option A) is the most straightforward fix."
}

# ── Run ─────────────────────────────────────────────────────────────────────
run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
