#!/usr/bin/env bash
###############################################################################
# Lab 04 – ImagePullBackOff
#
# Scenario : A Deployment references a container image tag that does not
#            exist, leaving pods stuck in ImagePullBackOff.
# Objective: Fix the image reference so all pods reach Running state.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="image-pull"
LAB_TITLE="Lab 04 – ImagePullBackOff"
LAB_DESC="
  ${BOLD}Scenario${NC}
  The development team pushed a new version of the ${CYAN}web-app${NC}
  deployment, but made a typo in the image tag. All pods are stuck
  in ${RED}ImagePullBackOff${NC} / ${RED}ErrImagePull${NC}.

  ${BOLD}Objective${NC}
  Fix the deployment so all 3 replicas reach ${GREEN}Running${NC} state.

  ${BOLD}Useful commands${NC}
    kubectl get pods
    kubectl describe pod <name>
    kubectl get deployment web-app -o yaml
"

# ── Deploy ──────────────────────────────────────────────────────────────────
deploy() {
    create_aks_cluster "$LAB_NAME"

    header "Injecting Lab Scenario"

    log "Creating deployment with bad image tag..."
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
        image: nginx:99.99.99
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
EOF
    ok "Deployment 'web-app' created"

    sleep 15

    echo ""
    separator
    err "Pods are in ImagePullBackOff / ErrImagePull!"
    kubectl get pods -l app=web-app --no-headers 2>/dev/null
    echo ""
    info "Investigate why the image cannot be pulled."
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
        info "Hint 1: Describe a pod and look at the Events section."
        info "  What error do you see about the image?"
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2: Check the container image tag in the deployment."
        info "  Does that tag actually exist on Docker Hub?"
    else
        info "Hint 3: The image tag 'nginx:99.99.99' does not exist."
        info "  Use a valid tag such as nginx:1.25 or nginx:latest."
    fi
}

# ── Solution ────────────────────────────────────────────────────────────────
solution() {
    echo ""
    header "Solution"
    info "Set the image to a valid tag:"
    echo -e "  ${CYAN}kubectl set image deployment/web-app nginx=nginx:1.25${NC}"
    echo ""
    info "Or edit the deployment:"
    echo -e "  ${CYAN}kubectl edit deployment web-app${NC}"
    info "  Change image from nginx:99.99.99 to nginx:1.25"
    echo ""
    info "Explanation: The tag 'nginx:99.99.99' does not exist on Docker Hub."
    info "Kubernetes cannot pull the image, so pods stay in ImagePullBackOff."
    info "Using a valid tag (e.g. 1.25, 1.26, latest) fixes the issue."
}

# ── Run ─────────────────────────────────────────────────────────────────────
run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
