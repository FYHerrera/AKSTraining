#!/usr/bin/env bash
# Lab 11 – Count Ready and schedulable nodes (no NoSchedule taint).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab11"; NS="cka-lab11"
LAB_TITLE="Lab 11 – Ready & schedulable nodes"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Write to ${CYAN}/tmp/question11.txt${NC} the number of Nodes that are
  Ready AND that do NOT carry any taint with effect NoSchedule.

  Tip: filter with kubectl + jq or with -o jsonpath."

deploy() { ensure_namespace "$NS"; ok "Inspect:  kubectl get nodes -o json | jq ..."; }

validate() {
    [[ -s /tmp/question11.txt ]] || { err "/tmp/question11.txt missing/empty"; return 1; }
    local user expected
    user=$(tr -d '[:space:]' < /tmp/question11.txt)
    expected=$(kubectl get nodes -o json \
        | jq '[ .items[] | select(any(.status.conditions[]; .type=="Ready" and .status=="True"))
               | select( (.spec.taints // []) | map(.effect=="NoSchedule") | any | not ) ] | length')
    [[ "$user" == "$expected" ]] || { err "File says '$user' but cluster has $expected matching nodes"; return 1; }
    ok "Correct ($expected)."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "kubectl get nodes -o wide  to see status & roles."
    else                       info "Use jq to filter Ready=True AND no taint with NoSchedule."
    fi
}

solution() {
cat <<EOF

  COUNT=\$(kubectl get nodes -o json | jq '[ .items[]
      | select(any(.status.conditions[]; .type=="Ready" and .status=="True"))
      | select((.spec.taints // []) | map(.effect=="NoSchedule") | any | not) ] | length')
  echo \$COUNT > /tmp/question11.txt

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
