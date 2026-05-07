#!/usr/bin/env bash
# Lab 31 – Prepare a Linux node for kubeadm (cri-dockerd + sysctl)  [Host-level]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab31"; NS="cka-lab31"
LAB_TITLE="Lab 31 – Prepare node for kubeadm  [host procedure]"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Prepare a Linux box (Docker installed) for kubeadm:
    1) Install cri-dockerd from a .deb (dpkg -i ~/cri-dockerd_*.deb)
    2) Enable & start the cri-docker service
    3) Add to /etc/sysctl.conf:
         net.bridge.bridge-nf-call-iptables = 1
         net.ipv6.conf.all.forwarding       = 1
         net.ipv4.ip_forward                = 1
         net.netfilter.nf_conntrack_max     = 131072
       and apply with 'sudo sysctl -p'.

  ${BOLD}Lab simulation${NC}
  Write the full set of commands into /tmp/q31-prep.txt.
"

deploy() { ensure_namespace "$NS"; touch /tmp/q31-prep.txt; ok "Write your prep commands into /tmp/q31-prep.txt"; }

validate() {
    local f=/tmp/q31-prep.txt
    grep -q "dpkg -i" "$f" || { err "Missing dpkg install of cri-dockerd"; return 1; }
    grep -q "systemctl enable.*cri-docker" "$f" || { err "Missing 'systemctl enable cri-docker'"; return 1; }
    grep -q "systemctl start.*cri-docker"  "$f" || { err "Missing 'systemctl start cri-docker'"; return 1; }
    grep -q "bridge-nf-call-iptables = 1" "$f" || { err "Missing bridge-nf-call-iptables = 1"; return 1; }
    grep -q "ipv6.conf.all.forwarding = 1" "$f" || { err "Missing ipv6 forwarding"; return 1; }
    grep -q "ip_forward = 1"             "$f"  || { err "Missing ip_forward"; return 1; }
    grep -q "nf_conntrack_max"           "$f"  || { err "Missing nf_conntrack_max"; return 1; }
    grep -q "sysctl -p"                  "$f"  || { err "Apply with 'sysctl -p'"; return 1; }
    ok "Node-prep procedure recorded."; return 0
}
hint() { info "Don't forget to apply with 'sudo sysctl -p' at the end."; }
solution() {
cat <<EOF

  cat > /tmp/q31-prep.txt <<'TXT'
  sudo dpkg -i ~/cri-dockerd_0.3.9.3-0.ubuntu-jammy_amd64.deb
  sudo systemctl enable cri-docker
  sudo systemctl start  cri-docker

  sudo tee -a /etc/sysctl.conf <<'EOF2'
  net.bridge.bridge-nf-call-iptables = 1
  net.ipv6.conf.all.forwarding       = 1
  net.ipv4.ip_forward                = 1
  net.netfilter.nf_conntrack_max     = 131072
  EOF2
  sudo sysctl -p
  TXT

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
