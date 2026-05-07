#!/usr/bin/env bash
# Lab 26 – JSONPath: list cert-manager CRDs and extract subject doc.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab26"; NS="cka-lab26"
LAB_TITLE="Lab 26 – JSONPath on cert-manager CRDs"
LAB_DESC="
  ${BOLD}Scenario${NC}
  cert-manager (or any CRD set) is installed.
    1) Save the list of all cert-manager CRDs (default kubectl table) to
       ${CYAN}~/resources.yaml${NC}.
    2) Extract the documentation of the ${CYAN}subject${NC} field of the
       ${CYAN}Certificate${NC} CR (any output format) to ${CYAN}~/subject.yaml${NC}.

  This lab installs the cert-manager CRDs to make the lab self-contained."

deploy() {
    ensure_namespace "$NS"
    if ! kubectl get crd certificates.cert-manager.io &>/dev/null; then
        log "Installing cert-manager CRDs (may take ~20s)..."
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml >/dev/null 2>&1 \
            || warn "Could not download CRDs (offline?). The lab still works if cert-manager is already installed."
    fi
    ok "Save CRD list to ~/resources.yaml and the subject schema to ~/subject.yaml."
}

validate() {
    [[ -s "$HOME/resources.yaml" ]] || { err "$HOME/resources.yaml missing"; return 1; }
    grep -q "cert-manager.io" "$HOME/resources.yaml" || { err "resources.yaml does not contain cert-manager CRDs"; return 1; }
    [[ -s "$HOME/subject.yaml" ]] || { err "$HOME/subject.yaml missing"; return 1; }
    grep -qi "subject" "$HOME/subject.yaml" || { err "subject.yaml does not mention 'subject'"; return 1; }
    ok "Files present and contain expected content."; return 0
}
hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "kubectl get crd | grep cert-manager > ~/resources.yaml"
    elif [[ $a -lt 4 ]]; then info "kubectl explain certificate.spec.subject --recursive > ~/subject.yaml"
    else                       info "JSONPath alt:  kubectl get crd certificates.cert-manager.io -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.subject}' > ~/subject.yaml"
    fi
}
solution() {
cat <<EOF

  kubectl get crd | grep cert-manager > ~/resources.yaml
  kubectl explain certificate.spec.subject --recursive > ~/subject.yaml

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
