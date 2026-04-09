#!/usr/bin/env bash
###############################################################################
# Lab 07 – NSG Blocking Traffic
#
# Scenario : An Azure NSG rule is blocking inbound traffic on port 80 to a
#            LoadBalancer service.
# Objective: Fix the NSG rule so the service is reachable externally.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="nsg-blocking"
LAB_TITLE="Lab 07 – NSG Blocking Inbound Traffic"
LAB_DESC="
  ${BOLD}Scenario${NC}
  A ${CYAN}web-app${NC} has been deployed with a LoadBalancer service and
  receives an external IP. However, external HTTP requests on port 80
  ${RED}time out${NC}. The issue is at the Azure networking level.

  ${BOLD}Objective${NC}
  Fix the networking issue so the service is reachable from outside
  via its external IP on port 80.

  ${BOLD}Useful commands${NC}
    kubectl get svc web-svc
    az network nsg list -g <MC_resource_group> -o table
    az network nsg rule list --nsg-name <nsg> -g <MC_resource_group> -o table
"

NSG_NAME=""
DENY_RULE_NAME="DenyInbound80"

# ── Deploy ──────────────────────────────────────────────────────────────────
deploy() {
    create_aks_cluster "$LAB_NAME"

    header "Injecting Lab Scenario"

    # Deploy app + LoadBalancer service
    log "Deploying web application with LoadBalancer..."
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
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
EOF
    ok "Deployment + LoadBalancer service created"

    # Wait for external IP
    log "Waiting for external IP (may take 1-2 minutes)..."
    local retries=0
    local ext_ip=""
    while [[ -z "$ext_ip" || "$ext_ip" == "null" ]] && [[ $retries -lt 30 ]]; do
        ext_ip=$(kubectl get svc web-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        ((retries++))
        sleep 10
    done

    if [[ -z "$ext_ip" || "$ext_ip" == "null" ]]; then
        err "Could not get external IP. Lab setup incomplete."
        return 1
    fi
    ok "External IP: $ext_ip"

    # Find NSG in MC_ resource group
    log "Configuring NSG deny rule..."
    NSG_NAME=$(az network nsg list -g "$MC_RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null)

    if [[ -z "$NSG_NAME" ]]; then
        err "Could not find NSG. Lab setup incomplete."
        return 1
    fi

    # Add deny rule with high priority
    az network nsg rule create \
        --resource-group "$MC_RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "$DENY_RULE_NAME" \
        --priority 100 \
        --direction Inbound \
        --access Deny \
        --protocol Tcp \
        --destination-port-ranges 80 \
        --source-address-prefixes '*' \
        --destination-address-prefixes '*' \
        -o none 2>/dev/null
    ok "NSG deny rule added"

    echo ""
    separator
    err "External traffic to port 80 is BLOCKED!"
    info "External IP:        $ext_ip"
    info "MC Resource Group:  $MC_RESOURCE_GROUP"
    info "NSG Name:           $NSG_NAME"
    echo ""
    info "The pods are running and the service has an IP, but HTTP"
    info "requests time out. The problem is at the Azure networking level."
    info "Use the menu below to validate once you've fixed the issue."
}

# ── Validate ────────────────────────────────────────────────────────────────
validate() {
    # Check if the deny rule still exists
    local rule_exists
    rule_exists=$(az network nsg rule show \
        --resource-group "$MC_RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "$DENY_RULE_NAME" 2>&1) || true

    if echo "$rule_exists" | grep -q "ResourceNotFound\|not found\|could not be found"; then
        ok "NSG deny rule has been removed!"

        # Bonus: try to reach the service
        local ext_ip
        ext_ip=$(kubectl get svc web-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -n "$ext_ip" ]]; then
            local response
            response=$(curl -s --connect-timeout 15 --max-time 20 "http://$ext_ip" 2>&1) || true
            if echo "$response" | grep -qi "nginx\|Welcome"; then
                ok "Service is reachable at http://$ext_ip"
            else
                warn "Rule removed but service may need a moment to become reachable."
            fi
        fi
        return 0
    else
        err "The deny NSG rule '$DENY_RULE_NAME' still exists."
        info "NSG: $NSG_NAME in resource group: $MC_RESOURCE_GROUP"
        return 1
    fi
}

# ── Hints ───────────────────────────────────────────────────────────────────
hint() {
    local attempt="${1:-0}"
    echo ""
    if [[ $attempt -lt 2 ]]; then
        info "Hint 1: The pods are running and the service has an external IP."
        info "  The issue is at the Azure networking level, not Kubernetes."
        info "  Look at Network Security Groups (NSG)."
    elif [[ $attempt -lt 4 ]]; then
        info "Hint 2: List NSG rules in the MC_ resource group:"
        info "  az network nsg rule list --nsg-name $NSG_NAME -g $MC_RESOURCE_GROUP -o table"
        info "  Look for a rule that denies inbound port 80."
    else
        info "Hint 3: There's a deny rule named '$DENY_RULE_NAME' blocking port 80."
        info "  Delete it with:"
        info "  az network nsg rule delete --nsg-name $NSG_NAME -g $MC_RESOURCE_GROUP -n $DENY_RULE_NAME"
    fi
}

# ── Solution ────────────────────────────────────────────────────────────────
solution() {
    echo ""
    header "Solution"
    info "Delete the NSG deny rule:"
    echo -e "  ${CYAN}az network nsg rule delete \\
    --resource-group $MC_RESOURCE_GROUP \\
    --nsg-name $NSG_NAME \\
    --name $DENY_RULE_NAME${NC}"
    echo ""
    info "Explanation: An NSG rule named '$DENY_RULE_NAME' with priority 100"
    info "was blocking all inbound TCP traffic on port 80. This overrides"
    info "the AKS-created rules that allow LoadBalancer traffic."
    info "Deleting the deny rule restores external access."
}

# ── Run ─────────────────────────────────────────────────────────────────────
run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
