#!/usr/bin/env bash
# Lab 23 – Helm: add repo, generate template, install.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab23"; NS="argocd"
LAB_TITLE="Lab 23 – Helm chart install"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Install Argo CD via Helm.
    1) Add repo:    helm repo add argo https://argoproj.github.io/argo-helm
    2) Update repos
    3) Generate the manifest of chart argo/argo-cd version 7.7.3
       to /tmp/argocd-template.yaml (with --set crds.install=false)
    4) Install the chart in namespace ${CYAN}argocd${NC}, name 'argocd', same version

  Helm 3 must be installed on your workstation.
"

deploy() {
    if ! command -v helm &>/dev/null; then
        err "Helm 3 not installed. Install it first: https://helm.sh/docs/intro/install/"; exit 1
    fi
    ensure_namespace "$NS"
    ok "Helm available. Add the repo and install the chart."
}

validate() {
    helm repo list 2>/dev/null | grep -q '^argo\s' || { err "Repo 'argo' not added"; return 1; }
    [[ -s /tmp/argocd-template.yaml ]] || { err "/tmp/argocd-template.yaml missing"; return 1; }
    helm -n "$NS" status argocd >/dev/null 2>&1 || { err "Release 'argocd' not installed in $NS"; return 1; }
    local v; v=$(helm -n "$NS" list -o json | jq -r '.[] | select(.name=="argocd") | .chart' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    [[ "$v" == "7.7.3" ]] || { err "Installed chart version is '$v', expected 7.7.3"; return 1; }
    ok "Argo CD 7.7.3 installed via Helm."; return 0
}
hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "helm repo add argo https://argoproj.github.io/argo-helm && helm repo update"
    elif [[ $a -lt 4 ]]; then info "helm template argocd argo/argo-cd --namespace $NS --version 7.7.3 --set crds.install=false > /tmp/argocd-template.yaml"
    else                       info "helm install argocd argo/argo-cd --namespace $NS --version 7.7.3 --set crds.install=false"
    fi
}
solution() {
cat <<EOF

  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm template argocd argo/argo-cd \\
       --namespace ${NS} --version 7.7.3 \\
       --set crds.install=false > /tmp/argocd-template.yaml
  helm install argocd argo/argo-cd \\
       --namespace ${NS} --version 7.7.3 \\
       --set crds.install=false

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
