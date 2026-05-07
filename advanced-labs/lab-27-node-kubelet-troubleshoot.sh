#!/usr/bin/env bash
# Lab 27 – Node / kubelet / API server troubleshooting  [Host-level]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab27"; NS="cka-lab27"
LAB_TITLE="Lab 27 – Node / kubelet troubleshooting  [host procedure]"
LAB_DESC="
  ${BOLD}Scenario${NC}
  A single-node kubeadm cluster was migrated. kubectl no longer works.
  Find which static-pod control plane component is broken (probably the
  API server) and restart what's needed. With external etcd, the API
  server's --etcd-servers flag may need updating.

  ${BOLD}Procedure (on the broken node)${NC}
    sudo crictl ps -a            # list containers, find failing ones
    sudo crictl logs <id>        # inspect crashlooping kube-apiserver
    sudo ls /etc/kubernetes/manifests/   # static pod manifests
    sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml   # fix --etcd-servers
    sudo systemctl restart kubelet
    journalctl -u kubelet -f

  ${BOLD}Lab simulation${NC}
  Record the diagnostic + fix steps in /tmp/q27-fix.txt.
"

deploy() { ensure_namespace "$NS"; touch /tmp/q27-fix.txt; ok "Write your investigation/fix into /tmp/q27-fix.txt"; }

validate() {
    grep -q "crictl ps" /tmp/q27-fix.txt || { err "Should investigate with 'crictl ps -a'"; return 1; }
    grep -q "kube-apiserver" /tmp/q27-fix.txt || { err "Should reference kube-apiserver"; return 1; }
    grep -q "systemctl restart kubelet" /tmp/q27-fix.txt || { err "Restart kubelet to pick up static-pod changes"; return 1; }
    ok "Procedure recorded."; return 0
}
hint() {
    local a="${1:-0}"
    [[ $a -lt 2 ]] && info "When kubectl is dead, use crictl on the node to inspect static pods." \
                   || info "Static pod manifests live in /etc/kubernetes/manifests/. Edit kube-apiserver.yaml; kubelet auto-recreates the pod."
}
solution() {
cat <<EOF

  cat > /tmp/q27-fix.txt <<'TXT'
  sudo crictl ps -a
  sudo crictl logs <kube-apiserver-id>
  sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml      # fix --etcd-servers=https://<new-ip>:2379
  sudo systemctl restart kubelet
  kubectl get pods -A
  TXT

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
