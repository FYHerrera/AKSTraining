#!/usr/bin/env bash
# Lab 06 – kubeadm cluster upgrade  [Host-level – documented procedure]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab06"; NS="cka-lab06"
LAB_TITLE="Lab 06 – Upgrade Control Plane via kubeadm  [host procedure]"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Upgrade a kubeadm-managed cluster from x.y to x.(y+1).

  ${BOLD}Docs${NC} https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/

  ${BOLD}Procedure (control-plane node)${NC}
    1. apt-mark unhold kubeadm && apt-get update && \\
       apt-get install -y kubeadm=1.NEW.0-* && apt-mark hold kubeadm
    2. sudo kubeadm upgrade plan
    3. sudo kubeadm upgrade apply v1.NEW.0
    4. kubectl drain <cp-node> --ignore-daemonsets
    5. apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.NEW.0-* kubectl=1.NEW.0-* && apt-mark hold kubelet kubectl
    6. sudo systemctl daemon-reload && sudo systemctl restart kubelet
    7. kubectl uncordon <cp-node>

  ${BOLD}Worker nodes${NC}
    1. sudo kubeadm upgrade node
    2. drain → upgrade kubelet/kubectl → restart kubelet → uncordon

  ${BOLD}Lab simulation${NC}
  This lab records your INTENDED upgrade plan in /tmp/q06-upgrade.txt.
  It checks the file contains the four critical commands.
"

deploy() { ensure_namespace "$NS"; touch /tmp/q06-upgrade.txt; ok "Write your upgrade plan into /tmp/q06-upgrade.txt"; }

validate() {
    local need=("kubeadm upgrade plan" "kubeadm upgrade apply" "drain" "systemctl restart kubelet")
    for n in "${need[@]}"; do
        grep -q "$n" /tmp/q06-upgrade.txt 2>/dev/null || { err "Plan must mention: '$n'"; return 1; }
    done
    ok "Upgrade plan covers the required steps."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Always start with 'kubeadm upgrade plan' to see target versions."
    else                       info "Order: install new kubeadm → plan → apply → drain → upgrade kubelet → restart kubelet → uncordon."
    fi
}

solution() {
cat <<EOF

  cat > /tmp/q06-upgrade.txt <<'TXT'
  # Control plane node
  apt-mark unhold kubeadm && apt-get install -y kubeadm=1.NEW.0-*
  apt-mark hold kubeadm
  sudo kubeadm upgrade plan
  sudo kubeadm upgrade apply v1.NEW.0
  kubectl drain <cp-node> --ignore-daemonsets
  apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.NEW.0-* kubectl=1.NEW.0-*
  apt-mark hold kubelet kubectl
  sudo systemctl daemon-reload
  sudo systemctl restart kubelet
  kubectl uncordon <cp-node>
  TXT

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
