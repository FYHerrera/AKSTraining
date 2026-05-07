#!/usr/bin/env bash
# Lab 10 – Fix node Not Ready (kubelet stopped & disabled)  [Host-level]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab10"; NS="cka-lab10"
LAB_TITLE="Lab 10 – Fix node NotReady (kubelet)  [host procedure]"
LAB_DESC="
  ${BOLD}Scenario${NC}
  A worker node shows ${CYAN}NotReady${NC}. The kubelet service has been
  STOPPED and DISABLED on the node.

  ${BOLD}Procedure (SSH into the node)${NC}
    sudo systemctl status kubelet
    sudo systemctl enable kubelet
    sudo systemctl start kubelet
    sudo journalctl -u kubelet -f
  Wait for kubectl get nodes to show 'Ready'.

  ${BOLD}Lab simulation${NC}
  Record the exact remediation commands in /tmp/q10-fix.txt.
"

deploy() { ensure_namespace "$NS"; touch /tmp/q10-fix.txt; ok "Write your remediation steps into /tmp/q10-fix.txt"; }

validate() {
    grep -q "systemctl enable kubelet" /tmp/q10-fix.txt || { err "Missing 'systemctl enable kubelet'"; return 1; }
    grep -q "systemctl start kubelet"  /tmp/q10-fix.txt || { err "Missing 'systemctl start kubelet'"; return 1; }
    ok "Procedure recorded."; return 0
}
hint() { info "On the node:  sudo systemctl enable --now kubelet"; }
solution() {
cat <<EOF

  cat > /tmp/q10-fix.txt <<'TXT'
  sudo systemctl enable kubelet
  sudo systemctl start kubelet
  sudo systemctl status kubelet
  TXT

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
