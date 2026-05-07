#!/usr/bin/env bash
# Lab 16 – Drain a node, ignoring DaemonSets.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab16"; NS="cka-lab16"
LAB_TITLE="Lab 16 – Drain a node"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Pick the first non-control-plane node in the cluster and drain it
  (cordon + evict) using ${CYAN}--ignore-daemonsets${NC}.
  Validation cordons-checks the node afterwards.

  ${BOLD}Docs${NC} https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/
"

TARGET_NODE_FILE="/tmp/q16-node.txt"

deploy() {
    ensure_namespace "$NS"
    local n
    n=$(kubectl get nodes -o json | jq -r '[.items[]
            | select((.metadata.labels."node-role.kubernetes.io/control-plane" // "") != "true")
            | .metadata.name][0]')
    [[ -z "$n" || "$n" == "null" ]] && n="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
    echo "$n" > "$TARGET_NODE_FILE"
    ok "Target node: $n  (saved in $TARGET_NODE_FILE). Drain it with --ignore-daemonsets."
}

validate() {
    local n; n="$(cat "$TARGET_NODE_FILE" 2>/dev/null)"
    [[ -z "$n" ]] && { err "Target node not recorded"; return 1; }
    local sched; sched="$(kubectl get node "$n" -o jsonpath='{.spec.unschedulable}')"
    [[ "$sched" == "true" ]] || { err "Node $n is not cordoned"; return 1; }
    local podcount
    podcount=$(kubectl get pods -A --field-selector=spec.nodeName="$n" -o json \
        | jq '[.items[] | select(.metadata.ownerReferences[0].kind!="DaemonSet") | select(.status.phase=="Running")] | length')
    [[ "$podcount" -eq 0 ]] || { err "$podcount non-DS pods still running on $n"; return 1; }
    ok "Node $n successfully drained (and stays cordoned)."
    info "Run 'kubectl uncordon $n' afterwards to restore scheduling."
    return 0
}
hint() { info "kubectl drain \$(cat $TARGET_NODE_FILE) --ignore-daemonsets --delete-emptydir-data"; }
solution() { echo -e "\n  ${CYAN}kubectl drain \$(cat $TARGET_NODE_FILE) --ignore-daemonsets --delete-emptydir-data${NC}\n"; }

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
