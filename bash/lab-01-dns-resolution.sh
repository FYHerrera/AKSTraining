#!/usr/bin/env bash
###############################################################################
# Lab 01 – DNS Resolution Failure
#
# Scenario : A NetworkPolicy blocks all egress traffic in the default
#            namespace, preventing pods from resolving DNS names.
# Objective: Identify and fix the NetworkPolicy so pods can resolve DNS.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="dns-resolution"
LAB_TITLE="Lab 01 – DNS Resolution Failure"
LAB_DESC="
  ${BOLD}Scenario${NC}
  A team deployed a NetworkPolicy to restrict traffic, but they
  accidentally blocked ALL egress — including DNS (port 53).
  Pods in the ${CYAN}default${NC} namespace can no longer resolve service names.

  ${BOLD}Objective${NC}
  Fix the issue so the test pod ${CYAN}dns-test${NC} can resolve DNS names.

  ${BOLD}Useful commands${NC}
    kubectl get networkpolicy
    kubectl describe networkpolicy <name>
    kubectl exec dns-test -- nslookup kubernetes.default
"

# ── Deploy ──────────────────────────────────────────────────────────────────
deploy() {
    create_aks_cluster "$LAB_NAME"

    header "Injecting Lab Scenario"

    # NetworkPolicy: deny all egress
    log "Applying restrictive NetworkPolicy..."
    kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF
    ok "NetworkPolicy applied"

    # Test pod
    log "Deploying test pod..."
    kubectl run dns-test --image=busybox:1.36 --restart=Never \
        -- sh -c "sleep 3600" 2>/dev/null || true
    kubectl wait --for=condition=Ready pod/dns-test --timeout=120s &>/dev/null
    ok "Test pod 'dns-test' is running"

    # Deploy a service to test DNS
    kubectl run web --image=nginx:1.25 --labels="app=web" 2>/dev/null || true
    kubectl expose pod web --port=80 --name=web-svc 2>/dev/null || true
    ok "Service 'web-svc' created"

    echo ""
    separator
    err "DNS resolution is BROKEN in the default namespace."
    info "Try:  kubectl exec dns-test -- nslookup kubernetes.default"
    info "Use the menu below to validate once you've fixed the issue."
}

# ── Validate ────────────────────────────────────────────────────────────────
validate() {
    local result
    result=$(kubectl exec dns-test -- nslookup kubernetes.default 2>&1) || true

    if echo "$result" | grep -q "Address.*10\."; then
        ok "DNS resolution is working!"
        return 0
    else
        err "DNS resolution still failing."
        err "Output: $(echo "$result" | head -3)"
        return 1
    fi
}

# ── Hints ───────────────────────────────────────────────────────────────────
hint() {
    local attempt="${1:-0}"
    echo ""
    if [[ $attempt -lt 2 ]]; then
        info "Hint 1: Inspect the NetworkPolicies in the default namespace."
        info "  kubectl get networkpolicy"
        info "  kubectl describe networkpolicy <name>"
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2: The NetworkPolicy is blocking ALL egress traffic."
        info "  DNS uses UDP/TCP port 53. Egress to CoreDNS must be allowed."
    else
        info "Hint 3: Either delete the policy or add an egress rule for DNS."
        info "  Option A: kubectl delete networkpolicy deny-all-egress"
        info "  Option B: Edit the policy to allow port 53 to kube-dns."
    fi
}

# ── Solution ────────────────────────────────────────────────────────────────
solution() {
    echo ""
    header "Solution"
    info "Option A – Delete the restrictive policy:"
    echo -e "  ${CYAN}kubectl delete networkpolicy deny-all-egress${NC}"
    echo ""
    info "Option B – Allow DNS egress while keeping the policy:"
    cat <<'SOL'

  kubectl apply -f - <<EOF
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: deny-all-egress
    namespace: default
  spec:
    podSelector: {}
    policyTypes:
    - Egress
    egress:
    - to:
      - namespaceSelector: {}
      ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
  EOF

SOL
    info "Explanation: The original policy had no egress rules, blocking"
    info "everything including DNS. Adding an egress rule for port 53"
    info "restores DNS resolution while still restricting other traffic."
}

# ── Run ─────────────────────────────────────────────────────────────────────
run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
