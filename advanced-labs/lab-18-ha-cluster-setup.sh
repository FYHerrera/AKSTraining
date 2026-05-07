#!/usr/bin/env bash
# Lab 18 – HA cluster setup with kubeadm  [Host-level – documented procedure]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab18"; NS="cka-lab18"
LAB_TITLE="Lab 18 – HA kubeadm cluster setup  [host procedure]"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Set up a highly available kubeadm cluster (3 control plane + N workers)
  with stacked etcd, configure RBAC.

  ${BOLD}Docs${NC}
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
    https://kubernetes.io/docs/reference/access-authn-authz/rbac/

  ${BOLD}Outline${NC}
    1. Provision a TCP load balancer in front of the 3 CP nodes (port 6443).
    2. On the FIRST CP node:
         sudo kubeadm init --control-plane-endpoint <LB_DNS>:6443 \\
              --upload-certs --pod-network-cidr=10.244.0.0/16
    3. Save the two join commands printed by kubeadm.
    4. On the OTHER CP nodes:
         sudo kubeadm join <LB_DNS>:6443 --token <T> \\
              --discovery-token-ca-cert-hash sha256:<H> \\
              --control-plane --certificate-key <K>
    5. On WORKER nodes:
         sudo kubeadm join <LB_DNS>:6443 --token <T> \\
              --discovery-token-ca-cert-hash sha256:<H>
    6. Apply a CNI (Calico/Flannel/Cilium).
    7. Configure RBAC: e.g. ClusterRoleBindings, NetworkPolicies, audit policy.

  ${BOLD}Lab simulation${NC}
  Record your full plan in /tmp/q18-ha.txt — validation looks for the key flags.
"

deploy() { ensure_namespace "$NS"; touch /tmp/q18-ha.txt; ok "Write your HA setup plan into /tmp/q18-ha.txt"; }

validate() {
    local need=("kubeadm init" "control-plane-endpoint" "upload-certs" "kubeadm join" "--control-plane" "kubeadm join" "CNI")
    for n in "${need[@]}"; do grep -q "$n" /tmp/q18-ha.txt || { err "Plan should mention: '$n'"; return 1; }; done
    ok "HA plan covers the required steps."; return 0
}
hint() { info "Critical flags:  --control-plane-endpoint, --upload-certs (init);  --control-plane --certificate-key (join)."; }
solution() {
cat <<EOF

  cat > /tmp/q18-ha.txt <<'TXT'
  # Provision LB → forward TCP/6443 to 3 control-plane VMs

  # On cp-1
  sudo kubeadm init --control-plane-endpoint cp-lb.example.com:6443 \\
       --upload-certs --pod-network-cidr=10.244.0.0/16

  # Join other CP nodes
  sudo kubeadm join cp-lb.example.com:6443 --token <T> \\
       --discovery-token-ca-cert-hash sha256:<H> \\
       --control-plane --certificate-key <K>

  # Join workers
  sudo kubeadm join cp-lb.example.com:6443 --token <T> \\
       --discovery-token-ca-cert-hash sha256:<H>

  # Install CNI (Calico)
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
  TXT

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
