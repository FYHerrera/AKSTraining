#!/usr/bin/env bash
###############################################################################
# advanced-labs/real-life-scenarios/rls-01-nginx-to-agc.sh
#
# Real Life Scenario 01 – NGINX Ingress → Application Gateway for Containers
#
# Reference:
#   https://techcommunity.microsoft.com/blog/appsonazureblog/
#   after-ingress-nginx-migrating-to-application-gateway-for-containers/4503110
#
# Overview:
#   Stage 1 – Deploy NGINX Ingress Controller + two apps with real annotations.
#   Stage 2 – Inventory existing Ingress resources and export manifests.
#   Stage 3 – Download & dry-run the AGC Migration Utility.
#   Stage 4 – Provision AGC + install ALB Controller (BYO or Managed).
#   Stage 5 – Generate Gateway API resources with the migration utility.
#   Stage 6 – Apply Gateway API resources and validate traffic.
#   Stage 7 – Decommission NGINX and remove old Ingress objects.
#
# Pre-requisites (checked at runtime):
#   kubectl → AKS cluster with Azure CNI / Azure CNI Overlay + Workload Identity
#   az CLI  → authenticated (az login) with Contributor access
#   helm 3
#   jq
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ── Variables ─────────────────────────────────────────────────────────────────
SCENARIO_NAME="rls-01-nginx-to-agc"
NS_APPS="nginx-migration-demo"
NS_NGINX="ingress-nginx"
NS_ALB="azure-alb-system"
LAB_TMPDIR="/tmp/agc-lab"
MANIFESTS_DIR="${LAB_TMPDIR}/manifests"
OUTPUT_DIR="${LAB_TMPDIR}/output"
MIGRATION_BIN="${LAB_TMPDIR}/agc-migration"

# Azure resource names (overridable via env before running)
AGC_NAME="${AGC_NAME:-agc-lab-demo}"
FRONTEND_NAME="${FRONTEND_NAME:-agc-lab-frontend}"
ALB_IDENTITY_NAME="${ALB_IDENTITY_NAME:-azure-alb-identity}"

# ── Helpers ───────────────────────────────────────────────────────────────────
pause_for_user() {
    echo
    echo -ne "${BOLD}  Press [Enter] to continue...${NC}"
    read -r
}

ask_yes_no() {
    local msg="$1"
    echo -ne "${YELLOW}  ${msg} (y/n): ${NC}"
    read -r resp
    [[ "${resp,,}" =~ ^y ]]
}

prompt_var() {
    local var_name="$1" prompt_msg="$2" default_val="${3:-}"
    local current_val="${!var_name:-}"
    if [[ -n "$current_val" ]]; then
        ok "${var_name} already set: ${current_val}"
        return
    fi
    if [[ -n "$default_val" ]]; then
        echo -ne "${CYAN}  ${prompt_msg} [${default_val}]: ${NC}"
    else
        echo -ne "${CYAN}  ${prompt_msg}: ${NC}"
    fi
    read -r input
    input="${input:-$default_val}"
    [[ -z "$input" ]] && { err "${var_name} is required."; exit 1; }
    eval "${var_name}=\"${input}\""
    export "${var_name?}"
}

stage_header() {
    local num="$1" title="$2"
    echo
    echo -e "${BOLD}${BLUE}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}  ║  STAGE ${num}  –  ${title}${NC}"
    echo -e "${BOLD}${BLUE}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
check_prerequisites_extended() {
    header "Pre-flight Checks"

    command -v kubectl &>/dev/null \
        || { err "kubectl not found."; exit 1; }
    ok "kubectl: $(kubectl version --client -o json 2>/dev/null | grep -oE '"gitVersion":"v[^"]+"' | head -1)"

    command -v az &>/dev/null \
        || { err "az CLI not found. Install: https://aka.ms/installazurecli"; exit 1; }
    ok "az CLI: $(az version --query '"azure-cli"' -otsv 2>/dev/null)"

    command -v helm &>/dev/null \
        || { err "helm 3 not found. Install: https://helm.sh/docs/intro/install/"; exit 1; }
    ok "helm: $(helm version --short)"

    command -v jq &>/dev/null \
        || { err "jq not found. Install with your package manager."; exit 1; }
    ok "jq: $(jq --version)"

    kubectl cluster-info &>/dev/null \
        || { err "No reachable cluster in current kubectl context."; exit 1; }
    ok "Cluster: $(kubectl config current-context)"

    # ── Azure CNI check ──
    # Try to detect via az aks show; fall back to a soft warning
    local ctx cluster_name
    ctx="$(kubectl config current-context)"
    cluster_name="${ctx##*/}"   # last segment after '/' in AKS contexts
    local net_plugin
    net_plugin=$(az aks show --name "$cluster_name" --query "networkProfile.networkPlugin" -otsv 2>/dev/null || echo "unknown")

    if [[ "$net_plugin" == "azure" ]]; then
        ok "Network plugin: Azure CNI (compatible with AGC)"
    elif [[ "$net_plugin" == "kubenet" ]]; then
        warn "Network plugin: Kubenet — AGC requires Azure CNI or Azure CNI Overlay."
        warn "Plan a CNI migration first: https://learn.microsoft.com/azure/aks/concepts-network-legacy-cni"
        ask_yes_no "Continue anyway? (learning / demo purposes only)" || exit 1
    else
        warn "Could not auto-detect network plugin ('${net_plugin}'). Ensure Azure CNI or Azure CNI Overlay."
    fi

    # ── Workload Identity check ──
    if kubectl get mutatingwebhookconfiguration \
            azure-wi-webhook-mutating-webhook-configuration &>/dev/null 2>&1; then
        ok "Workload Identity: webhook present (enabled)"
    else
        warn "Workload Identity webhook not detected. AGC requires it."
        warn "Enable: az aks update -n <cluster> -g <rg> --enable-workload-identity --enable-oidc-issuer"
    fi

    # ── ALB CLI extension ──
    if az extension show -n alb &>/dev/null 2>&1; then
        ok "az extension 'alb': installed"
    else
        log "Installing az extension 'alb' (required for AGC commands)..."
        az extension add -n alb --yes &>/dev/null
        ok "az extension 'alb' installed."
    fi

    echo
}

# ── Stage 1 ───────────────────────────────────────────────────────────────────
stage_1_deploy_nginx() {
    stage_header "1" "Deploy NGINX Ingress Controller + Sample Apps"

    info "This stage represents the BEFORE state you are migrating FROM."
    info "We install NGINX Ingress via Helm and deploy two apps that use"
    info "typical NGINX annotations (rewrite-target, ssl-redirect, backend-protocol,"
    info "limit-rps, proxy timeouts). These annotations are what the migration"
    info "utility will translate to Gateway API equivalents."
    echo
    pause_for_user

    ensure_namespace "$NS_APPS"
    ensure_namespace "$NS_NGINX"

    # ── NGINX Ingress Controller ──
    log "Adding ingress-nginx Helm repo..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    ok "Helm repos updated."

    if helm -n "$NS_NGINX" status ingress-nginx &>/dev/null 2>&1; then
        ok "NGINX Ingress Controller already installed – skipping."
    else
        log "Installing NGINX Ingress Controller (this may take ~2 min)..."
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace "$NS_NGINX" \
            --set controller.replicaCount=1 \
            --set controller.nodeSelector."kubernetes\.io/os"=linux \
            --wait --timeout 5m >/dev/null
        ok "NGINX Ingress Controller installed in namespace '${NS_NGINX}'."
    fi

    # ── App A – URL rewrite + regex paths ──
    log "Deploying app-a (URL rewrite annotation)..."
    kubectl -n "$NS_APPS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-a
  labels: { app: app-a }
spec:
  replicas: 2
  selector: { matchLabels: { app: app-a } }
  template:
    metadata: { labels: { app: app-a } }
    spec:
      containers:
      - name: app-a
        image: nginx:1.25
        ports: [{ containerPort: 80 }]
        readinessProbe:
          httpGet: { path: /, port: 80 }
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: app-a-svc
spec:
  selector: { app: app-a }
  ports: [{ port: 80, targetPort: 80 }]
YAML

    # ── App B – backend protocol + rate limiting ──
    log "Deploying app-b (backend-protocol + rate-limit annotations)..."
    kubectl -n "$NS_APPS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-b
  labels: { app: app-b }
spec:
  replicas: 2
  selector: { matchLabels: { app: app-b } }
  template:
    metadata: { labels: { app: app-b } }
    spec:
      containers:
      - name: app-b
        image: nginx:1.25
        ports: [{ containerPort: 80 }]
        readinessProbe:
          httpGet: { path: /, port: 80 }
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: app-b-svc
spec:
  selector: { app: app-b }
  ports: [{ port: 80, targetPort: 80 }]
YAML

    # ── Ingress resources with NGINX annotations ──
    mkdir -p "$MANIFESTS_DIR"

    cat > "${MANIFESTS_DIR}/ingress-app-a.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-a-ingress
  namespace: ${NS_APPS}
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
spec:
  ingressClassName: nginx
  rules:
  - host: app-a.example.com
    http:
      paths:
      - path: /api(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: app-a-svc
            port: { number: 80 }
YAML

    cat > "${MANIFESTS_DIR}/ingress-app-b.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-b-ingress
  namespace: ${NS_APPS}
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "30"
spec:
  ingressClassName: nginx
  rules:
  - host: app-b.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-b-svc
            port: { number: 80 }
YAML

    log "Applying Ingress resources..."
    kubectl apply -f "${MANIFESTS_DIR}/ingress-app-a.yaml" >/dev/null
    kubectl apply -f "${MANIFESTS_DIR}/ingress-app-b.yaml" >/dev/null

    log "Waiting for both deployments to become ready..."
    kubectl -n "$NS_APPS" rollout status deploy/app-a --timeout=120s >/dev/null
    kubectl -n "$NS_APPS" rollout status deploy/app-b --timeout=120s >/dev/null

    echo
    ok "Stage 1 complete. Current Ingress state:"
    kubectl -n "$NS_APPS" get ingress 2>/dev/null || true
    separator
}

# ── Stage 2 ───────────────────────────────────────────────────────────────────
stage_2_inventory() {
    stage_header "2" "Inventory – Know What You Have Before Migrating"

    info "Per the guide: before touching any manifests, understand your"
    info "existing Ingress resources, which annotations they use, and whether"
    info "any custom snippets or Lua configs will block migration."
    echo

    header "All Ingress Resources (all namespaces)"
    kubectl get ingress -A 2>/dev/null || warn "No Ingress resources found."
    echo

    header "NGINX Annotations in Use"
    kubectl get ingress -A -o json 2>/dev/null \
        | jq -r '
            .items[] |
            "─── " + .metadata.namespace + "/" + .metadata.name,
            ( .metadata.annotations
              | to_entries[]
              | select(.key | startswith("nginx.ingress.kubernetes.io"))
              | "  " + .key + ": " + .value
            )
        ' \
        | grep -v "^$" 2>/dev/null || warn "No NGINX-specific annotations found."
    echo

    info "Manifests saved to: ${MANIFESTS_DIR}/"
    ls -1 "${MANIFESTS_DIR}/"*.yaml 2>/dev/null || warn "No manifest files found."
    echo

    warn "Annotations that have NO AGC equivalent (will block migration):"
    warn "  nginx.ingress.kubernetes.io/configuration-snippet"
    warn "  nginx.ingress.kubernetes.io/server-snippet"
    warn "  nginx.ingress.kubernetes.io/lua-*"
    info "If any of these appear above, plan manual replacements before proceeding."
    echo

    ok "Stage 2 complete."
    separator
}

# ── Stage 3 ───────────────────────────────────────────────────────────────────
stage_3_migration_utility() {
    stage_header "3" "Download & Dry-Run AGC Migration Utility"

    info "The AGC Migration Utility converts Ingress → Gateway API resources."
    info "It does NOT touch your cluster. It reads manifests and outputs YAML."
    info "Repo: https://github.com/Azure/Application-Gateway-for-Containers-Migration-Utility"
    echo
    pause_for_user

    mkdir -p "$(dirname "$MIGRATION_BIN")"

    # ── Download binary ──
    if [[ -x "$MIGRATION_BIN" ]]; then
        ok "Migration utility already present: ${MIGRATION_BIN}"
    else
        local os arch
        os="$(uname -s | tr '[:upper:]' '[:lower:]')"   # linux | darwin
        arch="$(uname -m)"
        [[ "$arch" == "x86_64" ]]                        && arch="amd64"
        [[ "$arch" =~ ^(aarch64|arm64)$ ]]               && arch="arm64"

        local base_url="https://github.com/Azure/Application-Gateway-for-Containers-Migration-Utility/releases/latest/download"
        local download_url="${base_url}/agc-migration-${os}-${arch}"

        log "Downloading agc-migration for ${os}/${arch}..."
        info "  URL: ${download_url}"

        if curl -fsSL "${download_url}" -o "${MIGRATION_BIN}" 2>/dev/null; then
            chmod +x "${MIGRATION_BIN}"
            ok "Migration utility downloaded: ${MIGRATION_BIN}"
        else
            err "Download failed. Download manually from:"
            err "  https://github.com/Azure/Application-Gateway-for-Containers-Migration-Utility/releases"
            err "Place the binary at: ${MIGRATION_BIN}  (must be executable)"
            exit 1
        fi
    fi

    echo

    # ── Dry run against saved manifests ──
    header "Step 3a – Dry-Run (files mode)"
    info "Running dry-run against manifests in ${MANIFESTS_DIR}/ ..."
    echo

    "${MIGRATION_BIN}" files \
        --provider nginx \
        --ingress-class nginx \
        --dry-run \
        "${MANIFESTS_DIR}"/*.yaml 2>&1 || true

    echo

    # ── Show cluster-mode command for reference ──
    header "Step 3b – Alternative: Cluster Mode"
    info "To read Ingress resources directly from a live cluster instead:"
    echo -e "  ${CYAN}${MIGRATION_BIN} cluster --provider nginx --ingress-class nginx --dry-run${NC}"
    echo

    info "How to interpret the migration report:"
    echo -e "  ${GREEN}completed${NC}      – annotation fully translated to Gateway API"
    echo -e "  ${YELLOW}warning${NC}        – migrated with caveats; review generated output"
    echo -e "  ${YELLOW}not-supported${NC}  – no AGC equivalent; manual work required"
    echo -e "  ${RED}error${NC}          – migration failed; must be resolved before applying"
    echo

    ok "Stage 3 complete. Resolve any 'not-supported' or 'error' items before Stage 5."
    separator
}

# ── Stage 4 ───────────────────────────────────────────────────────────────────
stage_4_setup_agc() {
    stage_header "4" "Provision AGC + Install ALB Controller"

    info "Choose your AGC deployment model:"
    echo
    echo -e "  ${GREEN}[1]${NC}  BYO (Bring Your Own)  – you create the AGC resource via az CLI."
    echo -e "         Full control over the Azure resource lifecycle."
    echo -e "         Best for production / existing IaC pipelines."
    echo
    echo -e "  ${GREEN}[2]${NC}  Managed               – ALB Controller creates Azure resources."
    echo -e "         Define an ApplicationLoadBalancer CRD in Kubernetes."
    echo -e "         Simpler, but Azure resource lifecycle is tied to the CRD."
    echo
    echo -ne "${BOLD}  Choose [1/2]: ${NC}"
    read -r model_choice

    case "$model_choice" in
        1) _stage_4_byo ;;
        2) _stage_4_managed ;;
        *) warn "Invalid choice. Defaulting to BYO."; _stage_4_byo ;;
    esac

    echo

    # ── Install ALB Controller ──
    header "Install ALB Controller via Helm"
    info "The ALB Controller runs in your cluster, watches Gateway API resources,"
    info "and translates them into configuration on the AGC data plane."
    echo

    local client_id
    client_id=$(az identity show \
        --resource-group "$CLUSTER_RG" \
        --name "$ALB_IDENTITY_NAME" \
        --query clientId -otsv 2>/dev/null) || {
        err "Could not retrieve the managed identity client ID."
        err "Ensure the identity '${ALB_IDENTITY_NAME}' exists in resource group '${CLUSTER_RG}'."
        return 1
    }

    log "Installing ALB Controller (Helm OCI chart from mcr.microsoft.com)..."
    if helm -n "$NS_ALB" status alb-controller &>/dev/null 2>&1; then
        ok "ALB Controller already installed – skipping."
    else
        helm install alb-controller \
            oci://mcr.microsoft.com/application-lb/charts/alb-controller \
            --namespace "$NS_ALB" \
            --create-namespace \
            --set albController.namespace="$NS_ALB" \
            --set albController.podIdentity.clientID="$client_id" \
            --wait --timeout 5m
        ok "ALB Controller installed in namespace '${NS_ALB}'."
    fi

    log "Waiting for ALB Controller pods to be Ready..."
    kubectl -n "$NS_ALB" wait --for=condition=Ready pods \
        -l app.kubernetes.io/name=alb-controller \
        --timeout=120s >/dev/null 2>&1 \
        && ok "ALB Controller pods are Ready." \
        || warn "ALB Controller pods not yet Ready. Check: kubectl -n ${NS_ALB} get pods"

    ok "Stage 4 complete."
    separator
}

_stage_4_byo() {
    header "BYO Mode – Pre-create AGC Azure Resources"
    info "What you need:"
    info "  • A Resource Group where the AGC resource will live"
    info "  • A VNet with a subnet dedicated to AGC"
    info "    (the subnet will be delegated to Microsoft.ServiceNetworking/trafficControllers)"
    info "  • Contributor access on the cluster resource group"
    echo
    pause_for_user

    prompt_var CLUSTER_RG      "AKS Cluster Resource Group"
    prompt_var CLUSTER_NAME    "AKS Cluster Name"
    prompt_var VNET_RG         "VNet Resource Group"
    prompt_var VNET_NAME       "VNet Name"
    prompt_var AGC_SUBNET_NAME "AGC Delegated Subnet Name"

    local sub_id
    sub_id=$(az account show --query id -otsv)

    # ── Register resource providers ──
    log "Registering required resource providers (background)..."
    for rp in \
        Microsoft.ContainerService \
        Microsoft.Network \
        Microsoft.NetworkFunction \
        Microsoft.ServiceNetworking; do
        az provider register --namespace "$rp" >/dev/null 2>&1 &
    done
    wait
    ok "Resource providers registered."

    # ── Managed identity for ALB Controller ──
    log "Creating managed identity '${ALB_IDENTITY_NAME}' in '${CLUSTER_RG}'..."
    az identity create \
        --resource-group "$CLUSTER_RG" \
        --name "$ALB_IDENTITY_NAME" \
        --location "$(az group show -n "$CLUSTER_RG" --query location -otsv)" \
        --output none 2>/dev/null || ok "Identity already exists."

    local principal_id
    principal_id=$(az identity show -g "$CLUSTER_RG" -n "$ALB_IDENTITY_NAME" --query principalId -otsv)
    ok "Managed identity principal ID: ${principal_id}"

    # ── Federated credential (workload identity) ──
    local oidc_issuer
    oidc_issuer=$(az aks show \
        -g "$CLUSTER_RG" \
        -n "$CLUSTER_NAME" \
        --query "oidcIssuerProfile.issuerUrl" -otsv)
    log "Creating federated credential (workload identity)..."
    az identity federated-credential create \
        --name "alb-controller-federated" \
        --identity-name "$ALB_IDENTITY_NAME" \
        --resource-group "$CLUSTER_RG" \
        --issuer "$oidc_issuer" \
        --subject "system:serviceaccount:${NS_ALB}:alb-controller-serviceaccount" \
        --output none 2>/dev/null || ok "Federated credential already exists."
    ok "Federated credential configured."

    # ── Role assignments ──
    local rg_scope="/subscriptions/${sub_id}/resourceGroups/${CLUSTER_RG}"
    local subnet_id="/subscriptions/${sub_id}/resourceGroups/${VNET_RG}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${AGC_SUBNET_NAME}"

    log "Assigning 'AppGw for Containers Configuration Manager' on resource group..."
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role "AppGw for Containers Configuration Manager" \
        --scope "$rg_scope" \
        --output none 2>/dev/null || ok "Role already assigned."

    log "Assigning 'Network Contributor' on subnet..."
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role "Network Contributor" \
        --scope "$subnet_id" \
        --output none 2>/dev/null || ok "Role already assigned."

    # ── Delegate subnet ──
    log "Delegating subnet to Microsoft.ServiceNetworking/trafficControllers..."
    az network vnet subnet update \
        --resource-group "$VNET_RG" \
        --vnet-name "$VNET_NAME" \
        --name "$AGC_SUBNET_NAME" \
        --delegations "Microsoft.ServiceNetworking/trafficControllers" \
        --output none 2>/dev/null || ok "Subnet already delegated."
    ok "Subnet delegated."

    # ── Create AGC resource ──
    log "Creating Application Gateway for Containers: '${AGC_NAME}'..."
    az network alb create \
        --resource-group "$CLUSTER_RG" \
        --name "$AGC_NAME" \
        --output none 2>/dev/null || ok "AGC resource already exists."
    ok "AGC resource: ${AGC_NAME}"

    # ── Create Frontend ──
    log "Creating Frontend: '${FRONTEND_NAME}'..."
    az network alb frontend create \
        --resource-group "$CLUSTER_RG" \
        --alb-name "$AGC_NAME" \
        --name "$FRONTEND_NAME" \
        --output none 2>/dev/null || ok "Frontend already exists."
    ok "Frontend: ${FRONTEND_NAME}"

    # ── Subnet association ──
    log "Creating subnet association '${AGC_NAME}-association'..."
    az network alb association create \
        --resource-group "$CLUSTER_RG" \
        --alb-name "$AGC_NAME" \
        --name "${AGC_NAME}-association" \
        --subnet-id "$subnet_id" \
        --output none 2>/dev/null || ok "Association already exists."
    ok "Subnet association created."

    # Export for Stage 5
    export AGC_ID
    AGC_ID=$(az network alb show \
        -g "$CLUSTER_RG" \
        -n "$AGC_NAME" \
        --query id -otsv)
    export SUBNET_ID="$subnet_id"
    ok "AGC Resource ID exported: ${AGC_ID}"
}

_stage_4_managed() {
    header "Managed Mode – ALB Controller Manages Azure Resources"
    info "You define an ApplicationLoadBalancer CRD in Kubernetes."
    info "The ALB Controller provisions and manages the AGC Azure resource."
    echo
    pause_for_user

    prompt_var CLUSTER_RG      "AKS Cluster Resource Group"
    prompt_var CLUSTER_NAME    "AKS Cluster Name"
    prompt_var VNET_RG         "VNet Resource Group"
    prompt_var VNET_NAME       "VNet Name"
    prompt_var AGC_SUBNET_NAME "AGC Delegated Subnet Name"
    prompt_var NS_ALB_INFRA    "Namespace for ApplicationLoadBalancer CRD" "alb-infra"

    local sub_id
    sub_id=$(az account show --query id -otsv)

    log "Registering required resource providers..."
    for rp in \
        Microsoft.ContainerService \
        Microsoft.Network \
        Microsoft.NetworkFunction \
        Microsoft.ServiceNetworking; do
        az provider register --namespace "$rp" >/dev/null 2>&1 &
    done
    wait
    ok "Resource providers registered."

    log "Creating managed identity '${ALB_IDENTITY_NAME}'..."
    az identity create \
        --resource-group "$CLUSTER_RG" \
        --name "$ALB_IDENTITY_NAME" \
        --location "$(az group show -n "$CLUSTER_RG" --query location -otsv)" \
        --output none 2>/dev/null || ok "Identity already exists."

    local principal_id
    principal_id=$(az identity show -g "$CLUSTER_RG" -n "$ALB_IDENTITY_NAME" --query principalId -otsv)

    local oidc_issuer
    oidc_issuer=$(az aks show \
        -g "$CLUSTER_RG" \
        -n "$CLUSTER_NAME" \
        --query "oidcIssuerProfile.issuerUrl" -otsv)

    az identity federated-credential create \
        --name "alb-controller-federated" \
        --identity-name "$ALB_IDENTITY_NAME" \
        --resource-group "$CLUSTER_RG" \
        --issuer "$oidc_issuer" \
        --subject "system:serviceaccount:${NS_ALB}:alb-controller-serviceaccount" \
        --output none 2>/dev/null || ok "Federated credential already exists."

    local rg_scope="/subscriptions/${sub_id}/resourceGroups/${CLUSTER_RG}"
    local subnet_id="/subscriptions/${sub_id}/resourceGroups/${VNET_RG}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${AGC_SUBNET_NAME}"

    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role "AppGw for Containers Configuration Manager" \
        --scope "$rg_scope" \
        --output none 2>/dev/null || ok "Role already assigned."
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role "Network Contributor" \
        --scope "$subnet_id" \
        --output none 2>/dev/null || ok "Role already assigned."
    # Managed mode: Controller also needs Contributor to create the AGC resource
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role "Contributor" \
        --scope "$rg_scope" \
        --output none 2>/dev/null || ok "Contributor role already assigned."

    log "Delegating subnet to Microsoft.ServiceNetworking/trafficControllers..."
    az network vnet subnet update \
        --resource-group "$VNET_RG" \
        --vnet-name "$VNET_NAME" \
        --name "$AGC_SUBNET_NAME" \
        --delegations "Microsoft.ServiceNetworking/trafficControllers" \
        --output none 2>/dev/null || ok "Subnet already delegated."
    ok "Subnet delegated."

    ensure_namespace "$NS_ALB_INFRA"

    log "Applying ApplicationLoadBalancer CRD..."
    kubectl apply -f - <<YAML
apiVersion: alb.networking.azure.io/v1
kind: ApplicationLoadBalancer
metadata:
  name: ${AGC_NAME}
  namespace: ${NS_ALB_INFRA}
spec:
  associations:
  - ${subnet_id}
YAML
    ok "ApplicationLoadBalancer CRD applied."
    info "The ALB Controller will now provision the Azure resources."
    info "Monitor progress:"
    echo -e "  ${CYAN}kubectl -n ${NS_ALB_INFRA} get applicationloadbalancer ${AGC_NAME} -w${NC}"

    export SUBNET_ID="$subnet_id"
}

# ── Stage 5 ───────────────────────────────────────────────────────────────────
stage_5_generate_output() {
    stage_header "5" "Generate Gateway API Resources"

    info "The migration utility converts your Ingress resources into:"
    info "  • Gateway       – the entry point (replaces IngressClass)"
    info "  • HTTPRoute(s)  – routing rules (replaces Ingress rules + annotations)"
    info "  • Policy CRDs   – AGC-specific extensions (health probes, rewrites, etc.)"
    echo
    pause_for_user

    mkdir -p "$OUTPUT_DIR"

    if [[ -n "${AGC_ID:-}" ]]; then
        log "Generating output in BYO mode (AGC resource ID attached)..."
        "${MIGRATION_BIN}" files \
            --provider nginx \
            --ingress-class nginx \
            --byo-resource-id "${AGC_ID}" \
            --output-dir "${OUTPUT_DIR}" \
            "${MANIFESTS_DIR}"/*.yaml

    elif [[ -n "${SUBNET_ID:-}" ]]; then
        log "Generating output in Managed mode (subnet ID attached)..."
        "${MIGRATION_BIN}" files \
            --provider nginx \
            --ingress-class nginx \
            --managed-subnet-id "${SUBNET_ID}" \
            --output-dir "${OUTPUT_DIR}" \
            "${MANIFESTS_DIR}"/*.yaml
    else
        err "Neither AGC_ID nor SUBNET_ID is set."
        err "Run Stage 4 first, or set one of these environment variables:"
        err "  export AGC_ID='<AGC resource ID>'       # for BYO"
        err "  export SUBNET_ID='<delegated subnet ID>' # for Managed"
        return 1
    fi

    echo
    ok "Files generated in ${OUTPUT_DIR}/"

    header "Generated Files"
    ls -1 "${OUTPUT_DIR}/" 2>/dev/null || warn "Output directory is empty."
    echo

    header "Gateway Resource Preview"
    cat "${OUTPUT_DIR}"/gateway*.yaml 2>/dev/null \
        || warn "No gateway YAML found – check migration utility output above."
    echo

    header "HTTPRoute Resources Preview"
    cat "${OUTPUT_DIR}"/httproute*.yaml 2>/dev/null \
        || warn "No httproute YAML found – check migration utility output above."
    echo

    warn "Review the generated files carefully before applying to production."
    info "Specifically verify:"
    info "  • TLS secret references are correct (migration utility does NOT copy certs)"
    info "  • Backend service names and ports match what is deployed"
    info "  • Any 'not-supported' annotations from Stage 3 have been manually handled"

    ok "Stage 5 complete."
    separator
}

# ── Stage 6 ───────────────────────────────────────────────────────────────────
stage_6_apply_and_validate() {
    stage_header "6" "Apply Gateway API Resources & Validate"

    info "Strategy: run NGINX and AGC IN PARALLEL while you validate."
    info "NGINX keeps serving production traffic until you update DNS."
    info "Only perform the DNS cutover after confirming AGC routes correctly."
    echo

    ask_yes_no "Apply generated resources from ${OUTPUT_DIR}/ now?" || {
        info "Skipping apply. Run manually when ready:"
        echo -e "  ${CYAN}kubectl apply -f ${OUTPUT_DIR}/${NC}"
        return
    }

    log "Applying Gateway API resources..."
    kubectl apply -f "${OUTPUT_DIR}/"
    ok "Resources applied."
    echo

    # ── Wait for Gateway to be Programmed ──
    local gateway_name gateway_ns
    gateway_name=$(kubectl get gateway -A -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$gateway_name" ]]; then
        gateway_ns=$(kubectl get gateway -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "default")
        log "Waiting for Gateway '${gateway_name}' to reach Programmed=True (up to 3 min)..."
        local elapsed=0
        while [[ $elapsed -lt 180 ]]; do
            local status
            status=$(kubectl -n "${gateway_ns}" get gateway "${gateway_name}" \
                -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null \
                || echo "Unknown")
            if [[ "$status" == "True" ]]; then
                echo
                ok "Gateway '${gateway_name}' is Programmed."
                break
            fi
            echo -ne "\r  Waiting... ${elapsed}s  (Programmed=${status})"
            sleep 5; elapsed=$((elapsed+5))
        done
        echo
    fi

    header "AGC Frontend FQDN(s)"
    kubectl get gateway -A \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.addresses[0].value}{"\n"}{end}' \
        2>/dev/null | column -t \
        || warn "Could not retrieve Gateway addresses yet. Try again in a minute."
    echo

    header "HTTPRoutes"
    kubectl get httproute -A 2>/dev/null || warn "No HTTPRoutes found."
    echo

    info "Test your routes against the AGC FQDN (replace <FQDN> with the address above):"
    echo -e "  ${CYAN}curl -v -H 'Host: app-a.example.com' http://<FQDN>/api/${NC}"
    echo -e "  ${CYAN}curl -v -H 'Host: app-b.example.com' http://<FQDN>/${NC}"
    echo
    info "DNS Cutover steps:"
    info "  1. Get the AGC FQDN from the Gateway address above."
    info "  2. Create a CNAME record: your-hostname → <AGC FQDN>"
    info "  3. Lower TTL on existing DNS records before cutover."
    info "  4. Update the DNS records (or CNAME) to point to the AGC FQDN."
    info "  5. Monitor traffic in Azure Monitor / AGC access logs."
    echo

    ok "Stage 6 complete."
    separator
}

# ── Stage 7 ───────────────────────────────────────────────────────────────────
stage_7_decommission_nginx() {
    stage_header "7" "Decommission NGINX + Remove Old Ingress Resources"

    warn "Only proceed AFTER DNS has been updated and AGC is serving all traffic."
    warn "Having two ingress controllers watching the same resources causes conflicts."
    echo

    ask_yes_no "Confirm: DNS cutover is complete and AGC is handling all traffic?" || {
        warn "Decommission skipped. Re-run this stage after DNS cutover."
        return
    }

    # ── Remove Ingress objects ──
    log "Deleting old Ingress resources in '${NS_APPS}'..."
    kubectl delete ingress -n "$NS_APPS" --all 2>/dev/null \
        && ok "Ingress resources deleted." \
        || warn "No Ingress resources found."

    # ── Uninstall NGINX via Helm ──
    log "Uninstalling NGINX Ingress Controller (Helm)..."
    if helm -n "$NS_NGINX" status ingress-nginx &>/dev/null 2>&1; then
        helm uninstall ingress-nginx -n "$NS_NGINX"
        ok "NGINX Ingress Controller uninstalled."
    else
        warn "NGINX Helm release not found – already removed?"
    fi

    # ── Remove namespace ──
    kubectl delete ns "$NS_NGINX" --ignore-not-found &>/dev/null &
    ok "Namespace '${NS_NGINX}' deletion initiated."

    echo
    ok "NGINX decommissioned."

    header "Final State – Gateway API Resources"
    kubectl get gateway -A 2>/dev/null  || true
    kubectl get httproute -A 2>/dev/null || true
    echo

    ok "Stage 7 complete. Migration is finished!"
    separator
}

# ── Lab Cleanup ───────────────────────────────────────────────────────────────
cleanup_all() {
    echo; separator
    warn "This will remove ALL lab resources:"
    warn "  Namespaces : ${NS_APPS}  ${NS_NGINX}  ${NS_ALB}"
    warn "  Helm releases: ingress-nginx, alb-controller"
    warn "  Gateway API resources (all namespaces)"
    warn "  Local temp files: ${LAB_TMPDIR}/"
    echo

    ask_yes_no "Delete all lab resources?" || { warn "Cleanup cancelled."; return; }

    helm uninstall ingress-nginx -n "$NS_NGINX" 2>/dev/null || true
    helm uninstall alb-controller -n "$NS_ALB"  2>/dev/null || true

    kubectl delete gateway  -A --all 2>/dev/null || true
    kubectl delete httproute -A --all 2>/dev/null || true
    kubectl delete applicationloadbalancer -A --all 2>/dev/null || true

    for ns in "$NS_APPS" "$NS_NGINX" "$NS_ALB"; do
        kubectl delete ns "$ns" --ignore-not-found &>/dev/null &
    done
    wait

    rm -rf "${LAB_TMPDIR}/"
    ok "Lab resources cleaned up."
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    LAB_START_TIME=$(date +%s)
    init_logging "$SCENARIO_NAME"
    trap cleanup_all INT TERM

    header "Real Life Scenario 01"
    echo -e "  ${BOLD}NGINX Ingress → Application Gateway for Containers${NC}"
    echo
    echo -e "  ${CYAN}Reference:${NC}"
    echo -e "  https://techcommunity.microsoft.com/blog/appsonazureblog/"
    echo -e "  after-ingress-nginx-migrating-to-application-gateway-for-containers/4503110"
    echo
    echo -e "  ${BOLD}Why migrate?${NC}"
    echo -e "  The community ingress-nginx project entered end-of-life in March 2026."
    echo -e "  The AKS App Routing add-on has critical patches until November 2026 only."
    echo -e "  Application Gateway for Containers (AGC) is the recommended successor:"
    echo -e "    • Managed Azure data plane – no in-cluster ingress pods to maintain"
    echo -e "    • Built-in WAF, per-pod load balancing, near-instant config propagation"
    echo -e "    • Native Gateway API support"
    echo
    echo -e "  ${BOLD}Stages:${NC}"
    echo -e "    ${GREEN}1${NC}  Deploy NGINX Ingress + sample apps (the 'before' state)"
    echo -e "    ${GREEN}2${NC}  Inventory existing Ingress resources and annotations"
    echo -e "    ${GREEN}3${NC}  Download & dry-run AGC Migration Utility"
    echo -e "    ${GREEN}4${NC}  Provision AGC + install ALB Controller (BYO or Managed)"
    echo -e "    ${GREEN}5${NC}  Generate Gateway API resources"
    echo -e "    ${GREEN}6${NC}  Apply resources and validate traffic"
    echo -e "    ${GREEN}7${NC}  Decommission NGINX"
    separator
    echo
    pause_for_user

    check_prerequisites_extended

    stage_1_deploy_nginx
    pause_for_user

    stage_2_inventory
    pause_for_user

    stage_3_migration_utility
    pause_for_user

    stage_4_setup_agc
    pause_for_user

    stage_5_generate_output
    pause_for_user

    stage_6_apply_and_validate
    pause_for_user

    stage_7_decommission_nginx

    echo
    local elapsed=$(( $(date +%s) - LAB_START_TIME ))
    header "Migration Complete!"
    ok "Total time: $((elapsed/60))m $((elapsed%60))s"
    echo
    info "Further reading:"
    info "  AGC documentation:   https://aka.ms/agc"
    info "  Migration utility:   https://github.com/Azure/Application-Gateway-for-Containers-Migration-Utility"
    info "  Gateway API docs:    https://gateway-api.sigs.k8s.io/"
    echo
}

main "$@"
