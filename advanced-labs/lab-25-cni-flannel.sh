#!/usr/bin/env bash
# Lab 25 – Install Flannel and fix incorrect Pod CIDR.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab25"; NS="cka-lab25"
LAB_TITLE="Lab 25 – Install CNI (Flannel) + fix CIDR  [host/CNI scenario]"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Flannel was applied with the wrong Pod CIDR (10.244.0.0/16) but the
  cluster expects ${CYAN}10.245.0.0/16${NC}. Edit the kube-flannel ConfigMap,
  set Network=10.245.0.0/16, then restart the Flannel pods.

  ${BOLD}Quick procedure${NC}
    kubectl -n kube-system edit cm kube-flannel-cfg
    # change net-conf.json: \"Network\": \"10.245.0.0/16\"
    kubectl -n kube-system rollout restart ds kube-flannel-ds  # or delete pods
    kubectl describe node <name> | grep -i podcidr             # verify

  ${BOLD}Lab simulation${NC}
  This lab seeds a fake ${CYAN}kube-flannel-cfg${NC} ConfigMap in the
  ${CYAN}cka-lab25${NC} namespace with the wrong CIDR. Edit it.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata: { name: kube-flannel-cfg }
data:
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": { "Type": "vxlan" }
    }
YAML
    ok "Wrong CIDR seeded in ConfigMap kube-flannel-cfg. Fix the network to 10.245.0.0/16."
}

validate() {
    local cm; cm=$(kubectl -n "$NS" get cm kube-flannel-cfg -o jsonpath='{.data.net-conf\.json}')
    echo "$cm" | grep -q '"Network"[[:space:]]*:[[:space:]]*"10\.245\.0\.0/16"' \
        || { err "ConfigMap still has wrong Network. Got:\n$cm"; return 1; }
    ok "Network changed to 10.245.0.0/16."; return 0
}
hint() { info "kubectl -n $NS edit cm kube-flannel-cfg  →  change Network to 10.245.0.0/16"; }
solution() {
cat <<EOF

  kubectl -n ${NS} get cm kube-flannel-cfg -o yaml \\
    | sed 's|10.244.0.0/16|10.245.0.0/16|' \\
    | kubectl apply -f -
  # In a real cluster: kubectl -n kube-system rollout restart ds kube-flannel-ds

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
